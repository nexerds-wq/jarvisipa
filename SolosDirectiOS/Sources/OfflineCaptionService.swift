import Foundation
import Combine
import Speech
import AVFoundation

/// Runs a real microphone -> Speech -> subtitle pipeline. The glasses image
/// renderer is separate: a connected OLED alone does NOT prove transcription.
/// On-device speech is preferred; online speech is used only with explicit
/// user opt-in when an offline language recognizer is unavailable.
final class OfflineCaptionService: NSObject, ObservableObject {
    @Published var isListening = false
    @Published var status = "Select CAPTIONS HUD to activate microphone"
    @Published var partial = ""
    @Published var latestFinal = ""
    @Published var history = [String]()
    @Published var localeCode = "en-US"
    @Published var recognizedLanguage = "English"
    @Published var audioBuffers = 0
    @Published var recognizerMode = "Not started"
    @Published var microphoneRoute = "No microphone selected"

    var onSubtitle: ((String) -> Void)?
    var onFinal: ((String) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var restartTask: DispatchWorkItem?
    private var desired = false
    private var starting = false
    private var onDeviceOnly = true
    private var preferPhoneMicrophone = false
    private var lastDisplay = Date.distantPast
    private var lastCaptionDelivered = ""
    private var generation = 0
    private var tapInstalled = false
    private let requestLock = NSLock()
    private var activeSpeechRecognizer: SFSpeechRecognizer?
    private var observerTokens = [NSObjectProtocol]()
    private var failureCount = 0
    private var lastRestart = Date.distantPast
    private var buffersCaptured = 0
    private var recentUnexpectedRestarts = [Date]()
    private var audioInterrupted = false
    private var lastAudioConfiguration = Date.distantPast

    override init() {
        super.init()
        let notifications = NotificationCenter.default
        observerTokens.append(notifications.addObserver(
            forName:AVAudioSession.interruptionNotification,
            object:AVAudioSession.sharedInstance(),queue:.main) { [weak self] note in
            guard let self, self.desired else { return }
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.began.rawValue {
                self.audioInterrupted = true
                self.generation += 1
                self.restartTask?.cancel()
                self.restartTask = nil
                self.cleanup()
                self.status = "Mic interrupted by iOS; resuming when available"
            } else if raw == AVAudioSession.InterruptionType.ended.rawValue {
                self.audioInterrupted = false
                self.scheduleRestart(reason:"Microphone interruption ended")
            }
        })
        observerTokens.append(notifications.addObserver(
            forName:AVAudioSession.routeChangeNotification,
            object:AVAudioSession.sharedInstance(),queue:.main) { [weak self] _ in
            guard let self, self.desired else { return }
            // AudioSession.setCategory used by our own startup emits a route
            // change. Restarting an already healthy engine here creates an
            // endless stop/start feedback loop and rapidly exhausts resources.
            guard !self.audioInterrupted, !self.starting,
                  !self.engine.isRunning,
                  Date().timeIntervalSince(self.lastAudioConfiguration) > 1.5 else { return }
            self.scheduleRestart(reason:"Microphone route changed and engine stopped")
        })
        observerTokens.append(notifications.addObserver(
            forName:Notification.Name.AVAudioEngineConfigurationChange,
            object:engine,queue:.main) { [weak self] _ in
            guard let self, self.desired, !self.audioInterrupted,
                  !self.starting, !self.engine.isRunning,
                  Date().timeIntervalSince(self.lastAudioConfiguration) > 1.5 else { return }
            self.scheduleRestart(reason:"Audio engine configuration changed")
        })
    }

    /// Setting allowOnlineRecognition true allows Speech to use Apple's network
    /// recognition when on-device recognition is not supported for the language.
    func start(locale:String, name:String, allowOnlineRecognition:Bool = false, preferPhoneMicrophone:Bool = false) {
        stop()
        audioBuffers = 0
        buffersCaptured = 0
        lastDisplay = .distantPast
        lastCaptionDelivered = ""
        failureCount = 0
        recentUnexpectedRestarts.removeAll()
        audioInterrupted = false
        lastAudioConfiguration = .distantPast
        desired = true
        localeCode = locale
        recognizedLanguage = name
        onDeviceOnly = !allowOnlineRecognition
        self.preferPhoneMicrophone = preferPhoneMicrophone
        status = "Requesting microphone + Speech permissions for \(name)..."
        let expected = generation
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            DispatchQueue.main.async {
                guard let self, self.desired, self.generation == expected else { return }
                guard auth == .authorized else {
                    self.desired = false
                    self.status = "Speech Recognition permission denied. Enable it in iPhone Settings."
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                    DispatchQueue.main.async {
                        guard let self, self.desired, self.generation == expected else { return }
                        guard granted else {
                            self.desired = false
                            self.status = "Microphone permission denied. Enable it in iPhone Settings."
                            return
                        }
                        self.beginRecognition()
                    }
                }
            }
        }
    }

    private func beginRecognition() {
        guard desired, !starting, !isListening else { return }
        guard let speech = SFSpeechRecognizer(locale:Locale(identifier:localeCode)) else {
            status = "Speech does not support locale \(localeCode). Choose another source language."
            desired = false
            return
        }
        guard speech.isAvailable else {
            // If speech service is temporarily unavailable, show the reason.
            // Do not repeatedly start an invalid recording loop.
            status = "iOS Speech recognizer unavailable for \(recognizedLanguage). Check language and network."
            desired = false
            return
        }
        let offlineCapable = speech.supportsOnDeviceRecognition
        guard offlineCapable || !onDeviceOnly else {
            recognizerMode = "Offline language model missing"
            status = "No on-device \(recognizedLanguage) recognizer. Enable ALLOW ONLINE SPEECH and retry, or install a supported language."
            desired = false
            return
        }

        starting = true
        recognizer = speech
        // With explicit consent, let the system use network recognition
        // even when an offline model exists but is not producing results.
        let forceOffline = onDeviceOnly && offlineCapable
        recognizerMode = forceOffline ? "On-device speech" : "System speech (network allowed)"
        let captureRequest = SFSpeechAudioBufferRecognitionRequest()
        captureRequest.shouldReportPartialResults = true
        captureRequest.requiresOnDeviceRecognition = forceOffline
        captureRequest.taskHint = .dictation
        captureRequest.addsPunctuation = true
        captureRequest.contextualStrings = ["Hey Jarvis", "Hola", "Oye Jarvis", "navegación", "traducción"]
        request = captureRequest
        activeSpeechRecognizer = speech

        do {
            let audio = AVAudioSession.sharedInstance()
            lastAudioConfiguration = Date()
            if preferPhoneMicrophone {
                // Bluetooth headset HFP may have low far-field sensitivity.
                // Use the iPhone's microphones without echo processing for a
                // person speaking across the room.
                // A record-only session interrupts Apple Music. Mix with existing playback,
                // retaining Bluetooth A2DP output while recording with iPhone microphone.
                try audio.setCategory(.playAndRecord,mode:.default,
                                      options:[.mixWithOthers,.allowBluetoothA2DP,.defaultToSpeaker])
            } else {
                try audio.setCategory(.playAndRecord,mode:.default,
                                      options:[.mixWithOthers,.allowBluetoothHFP,.defaultToSpeaker])
            }
            try audio.setActive(true)
            if preferPhoneMicrophone,
               let builtIn = audio.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try audio.setPreferredInput(builtIn)
            }
            if !preferPhoneMicrophone {
                guard let solosMic = audio.availableInputs?.first(where: {
                    $0.portType == .bluetoothHFP &&
                    ($0.portName.localizedCaseInsensitiveContains("Solos") ||
                     $0.uid.localizedCaseInsensitiveContains("Solos"))
                }) else {
                    desired = false
                    starting = false
                    status = "SOLOS MIC UNAVAILABLE • Connect Solos Bluetooth microphone in iPhone Settings. No iPhone mic fallback."
                    cleanup()
                    return
                }
                try audio.setPreferredInput(solosMic)
            }
            microphoneRoute = audio.currentRoute.inputs.map(\.portName).joined(separator:", ")
            if microphoneRoute.isEmpty { microphoneRoute = "No audio input selected" }
            let input = engine.inputNode
            let format = input.outputFormat(forBus:0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                starting = false
                cleanup()
                scheduleRestart(reason:"Microphone input has no usable audio format")
                return
            }
            if tapInstalled {
                input.removeTap(onBus:0)
                tapInstalled = false
            }
            input.installTap(onBus:0,bufferSize:1024,format:format) { [weak self] buffer, _ in
                guard let self else { return }
                self.requestLock.lock()
                self.request?.append(buffer)
                self.requestLock.unlock()
                self.buffersCaptured += 1
                if self.buffersCaptured % 45 == 0 {
                    let count = self.buffersCaptured
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.desired else { return }
                        self.audioBuffers = count
                    }
                }
            }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            isListening = true
            starting = false
            failureCount = 0
            status = "\(recognizerMode) • \(recognizedLanguage) • \(microphoneRoute)"
            let current = generation
            startCaptionTask(speech,captureRequest,generation:current)
            scheduleCaptionTaskRotation(generation:current)
        } catch {
            starting = false
            cleanup()
            scheduleRestart(reason:"Audio start failed: \(error.localizedDescription)")
        }
    }

    private func scheduleCaptionTaskRotation(generation:Int) {
        DispatchQueue.main.asyncAfter(deadline:.now()+48) { [weak self] in
            guard let self, self.desired, self.generation == generation,
                  self.engine.isRunning else { return }
            self.rotateCaptionTask()
        }
    }

    private func rotateCaptionTask() {
        guard desired, isListening, engine.isRunning, !audioInterrupted,
              let speech = activeSpeechRecognizer else { return }
        generation += 1
        let current = generation
        task?.cancel()
        task = nil
        let next = SFSpeechAudioBufferRecognitionRequest()
        next.shouldReportPartialResults = true
        next.requiresOnDeviceRecognition = onDeviceOnly && speech.supportsOnDeviceRecognition
        next.taskHint = .dictation
        next.addsPunctuation = true
        next.contextualStrings = ["Hey Jarvis","Hola","Oye Jarvis","navegación","traducción"]
        requestLock.lock()
        request?.endAudio()
        request = next
        requestLock.unlock()
        startCaptionTask(speech,next,generation:current)
        scheduleCaptionTaskRotation(generation:current)
        status = "\(recognizerMode) • microphone remains active"
    }

    private func startCaptionTask(_ speech:SFSpeechRecognizer,
                                  _ captureRequest:SFSpeechAudioBufferRecognitionRequest,
                                  generation current:Int) {
            task = speech.recognitionTask(with:captureRequest) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self, self.desired, self.generation == current else { return }
                    if let result {
                        let words = result.bestTranscription.formattedString
                            .trimmingCharacters(in:.whitespacesAndNewlines)
                        if !words.isEmpty {
                            self.partial = words
                            // First partial appears immediately; later
                            // changed fragments can update up to ~7 times/s.
                            // HUD frame compression has its own independent
                            // pacing and latest-wins queue, so mic stays fast.
                            if words != self.lastCaptionDelivered &&
                               Date().timeIntervalSince(self.lastDisplay) >= 0.075 {
                                self.lastDisplay = Date()
                                self.lastCaptionDelivered = words
                                self.onSubtitle?(words)
                            }
                            if result.isFinal {
                                self.latestFinal = words
                                self.history.append(words)
                                if self.history.count > 50 { self.history.removeFirst() }
                                self.onFinal?(words)
                            }
                        }
                        if result.isFinal {
                            self.rotateCaptionTask()
                            return
                        }
                    }
                    if let error {
                        self.status = "Speech error: \(error.localizedDescription)"
                        self.rotateCaptionTask()
                    }
                }
            }

    }

    private func scheduleRestart(reason:String) {
        guard desired, !audioInterrupted, restartTask == nil else { return }
        let current = Date()
        guard current.timeIntervalSince(lastRestart) >= 0.4 else { return }
        let expectedRotation = reason == "Caption utterance completed" ||
            reason == "Rotating 48-second speech session"
        if expectedRotation {
            recentUnexpectedRestarts.removeAll()
        } else {
            recentUnexpectedRestarts.removeAll {
                current.timeIntervalSince($0) > 45
            }
            recentUnexpectedRestarts.append(current)
            // Automatic microphone recovery must never become a CPU/memory
            // restart storm when another app owns audio or the route is bad.
            if recentUnexpectedRestarts.count >= 6 {
                desired = false
                cleanup()
                status = "Speech paused after repeated audio errors. Switch HUD away and back to retry."
                return
            }
        }
        lastRestart = current
        generation += 1
        restartTask?.cancel()
        cleanup()
        failureCount += 1
        let delay = expectedRotation ? 0.35 : min(5.0,0.9 + Double(failureCount) * 0.45)
        status = "\(reason). Reconnecting mic..."
        let expected = generation
        let job = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.restartTask = nil
            guard self.desired, !self.audioInterrupted,
                  self.generation == expected else { return }
            self.beginRecognition()
        }
        restartTask = job
        DispatchQueue.main.asyncAfter(deadline:.now()+delay,execute:job)
    }

    private func cleanup() {
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus:0)
            tapInstalled = false
        }
        // Invalidate the task before ending audio to avoid stale callbacks
        // from previous speech sessions.
        task?.cancel()
        task = nil
        requestLock.lock()
        request?.endAudio()
        request = nil
        requestLock.unlock()
        activeSpeechRecognizer = nil
        isListening = false
        starting = false
    }

    func stop() {
        desired = false
        generation += 1
        restartTask?.cancel()
        restartTask = nil
        cleanup()
        status = "Captions paused (mic released)"
        recognizerMode = "Stopped"
    }

    func clear() {
        partial = ""
        latestFinal = ""
        history.removeAll()
    }

    deinit {
        desired = false
        restartTask?.cancel()
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
