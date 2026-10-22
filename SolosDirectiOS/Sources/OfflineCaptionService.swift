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
    private var lastDisplay = Date.distantPast
    private var generation = 0
    private var tapInstalled = false
    private var observerTokens = [NSObjectProtocol]()
    private var failureCount = 0
    private var lastRestart = Date.distantPast
    private var buffersCaptured = 0

    override init() {
        super.init()
        let notifications = NotificationCenter.default
        observerTokens.append(notifications.addObserver(
            forName:AVAudioSession.interruptionNotification,
            object:AVAudioSession.sharedInstance(),queue:.main) { [weak self] note in
            guard let self, self.desired else { return }
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.began.rawValue {
                self.generation += 1
                self.restartTask?.cancel()
                self.cleanup()
                self.status = "Mic interrupted by iOS; resuming when available"
            } else if raw == AVAudioSession.InterruptionType.ended.rawValue {
                self.scheduleRestart(reason:"Microphone interruption ended")
            }
        })
        observerTokens.append(notifications.addObserver(
            forName:AVAudioSession.routeChangeNotification,
            object:AVAudioSession.sharedInstance(),queue:.main) { [weak self] _ in
            guard let self, self.desired else { return }
            // Route changes can invalidate AVAudioEngine's input format.
            self.scheduleRestart(reason:"Microphone route changed")
        })
        observerTokens.append(notifications.addObserver(
            forName:Notification.Name.AVAudioEngineConfigurationChange,
            object:engine,queue:.main) { [weak self] _ in
            guard let self, self.desired else { return }
            self.scheduleRestart(reason:"Audio configuration changed")
        })
    }

    /// Setting allowOnlineRecognition true allows Speech to use Apple's network
    /// recognition when on-device recognition is not supported for the language.
    func start(locale:String, name:String, allowOnlineRecognition:Bool = false) {
        stop()
        audioBuffers = 0
        buffersCaptured = 0
        lastDisplay = .distantPast
        failureCount = 0
        desired = true
        localeCode = locale
        recognizedLanguage = name
        onDeviceOnly = !allowOnlineRecognition
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
        request = captureRequest

        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord,mode:.default,
                                  options:[.defaultToSpeaker,.allowBluetooth])
            try audio.setActive(true)
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
                captureRequest.append(buffer)
                guard let self else { return }
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
            status = "\(recognizerMode) • MIC ACTIVE • \(recognizedLanguage)"
            let current = generation
            // Recognition sessions can expire. Rotate proactively so the
            // listener keeps working while the HUD remains selected.
            DispatchQueue.main.asyncAfter(deadline:.now()+48) { [weak self] in
                guard let self, self.desired, self.generation == current else { return }
                self.scheduleRestart(reason:"Rotating 48-second speech session")
            }
            task = speech.recognitionTask(with:captureRequest) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self, self.desired, self.generation == current else { return }
                    if let result {
                        let words = result.bestTranscription.formattedString
                            .trimmingCharacters(in:.whitespacesAndNewlines)
                        if !words.isEmpty {
                            self.partial = words
                            if Date().timeIntervalSince(self.lastDisplay) >= 0.7 {
                                self.lastDisplay = Date()
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
                            self.scheduleRestart(reason:"Caption utterance completed")
                            return
                        }
                    }
                    if let error {
                        self.status = "Speech error: \(error.localizedDescription)"
                        self.scheduleRestart(reason:"Speech recognizer stopped")
                    }
                }
            }
        } catch {
            starting = false
            cleanup()
            scheduleRestart(reason:"Audio start failed: \(error.localizedDescription)")
        }
    }

    private func scheduleRestart(reason:String) {
        guard desired else { return }
        guard Date().timeIntervalSince(lastRestart) >= 0.4 else { return }
        lastRestart = Date()
        generation += 1
        restartTask?.cancel()
        cleanup()
        failureCount += 1
        let delay = min(5.0,0.9 + Double(failureCount) * 0.45)
        status = "\(reason). Reconnecting mic..."
        let expected = generation
        let job = DispatchWorkItem { [weak self] in
            guard let self, self.desired, self.generation == expected else { return }
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
        request?.endAudio()
        request = nil
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
