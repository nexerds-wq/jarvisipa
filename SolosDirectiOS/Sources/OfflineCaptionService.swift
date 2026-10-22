import SwiftUI
import Combine
import Speech
import AVFoundation

/// iOS on-device speech recognition. Audio isn't sent to cloud services.
/// Speech language packs and locale support vary by OS/device.
final class OfflineCaptionService: NSObject, ObservableObject {
    @Published var isListening = false
    @Published var status = "Tap Start for fully offline captions"
    @Published var partial = ""
    @Published var latestFinal = ""
    @Published var history = [String]()
    @Published var localeCode = "en-US"
    @Published var recognizedLanguage = "English"

    var onSubtitle: ((String) -> Void)?
    var onFinal: ((String) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var restartTask: DispatchWorkItem?
    private var desired = false
    private var starting = false
    private var lastDisplay = Date.distantPast
    private var generation = 0
    private var tapInstalled = false

    func start(locale: String, name: String) {
        stop()
        desired = true
        localeCode = locale
        recognizedLanguage = name
        status = "Initializing live captions for \(name)..."
        let expected = generation
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            DispatchQueue.main.async {
                guard let self, self.desired, self.generation == expected else { return }
                guard auth == .authorized else {
                    self.desired = false
                    self.status = "Speech permission denied. Allow Speech Recognition in Settings."
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                    DispatchQueue.main.async {
                        guard let self, self.desired,
                              self.generation == expected else { return }
                        guard granted else {
                            self.desired = false
                            self.status = "Microphone permission denied"
                            return
                        }
                        self.recognize()
                    }
                }
            }
        }
    }
    private func recognize() {
        guard desired, !starting else { return }
        let speech = SFSpeechRecognizer(locale: Locale(identifier: localeCode))
        guard let speech, speech.isAvailable, speech.supportsOnDeviceRecognition else {
            status = "No OFFLINE speech pack for \(recognizedLanguage) on this phone. Try another language or check iOS language settings."
            desired = false
            isListening = false
            return
        }
        starting = true
        recognizer = speech
        let next = SFSpeechAudioBufferRecognitionRequest()
        next.shouldReportPartialResults = true
        next.requiresOnDeviceRecognition = true
        next.contextualStrings = ["Hey Jarvis", "Jarvis", "caption", "translate"]
        request = next
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: [])
            try audio.setActive(true, options: [])
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                next.append(buffer)
            }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            isListening = true
            status = "ON DEVICE • \(recognizedLanguage) • listening"
            let sequence = generation
            DispatchQueue.main.asyncAfter(deadline:.now()+48) { [weak self] in
                guard let self, self.desired, sequence == self.generation else { return }
                self.reboot()
            }
            task = speech.recognitionTask(with: next) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self, self.desired, sequence == self.generation else { return }
                    if let result {
                        let words = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !words.isEmpty {
                            self.partial = words
                            // Limit Bluetooth updates: the glasses are a small, slow display.
                            if Date().timeIntervalSince(self.lastDisplay) > 1.15 {
                                self.lastDisplay = Date()
                                self.onSubtitle?(words)
                            }
                        }
                        if result.isFinal {
                            if !words.isEmpty {
                                self.latestFinal = words
                                self.history.append(words)
                                if self.history.count > 40 { self.history.removeFirst() }
                                self.onFinal?(words)
                            }
                            self.reboot()
                            return
                        }
                    }
                    if error != nil { self.reboot() }
                }
            }
            starting = false
        } catch {
            starting = false
            desired = false
            cleanup()
            status = "Audio setup failed: \(error.localizedDescription)"
        }
    }
    private func reboot() {
        guard desired else { return }
        cleanup()
        generation += 1
        status = "Restarting offline speech listener..."
        restartTask?.cancel()
        let job = DispatchWorkItem { [weak self] in self?.recognize() }
        restartTask = job
        DispatchQueue.main.asyncAfter(deadline: .now()+0.65, execute: job)
    }
    private func cleanup() {
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isListening = false
    }
    func stop() {
        desired = false
        generation += 1
        restartTask?.cancel()
        restartTask = nil
        cleanup()
        status = "Offline captions stopped"
    }
    func clear() {
        partial = ""
        latestFinal = ""
        history.removeAll()
    }
    deinit { desired = false; restartTask?.cancel() }
}
