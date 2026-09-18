import Foundation
import AVFoundation
import Speech

@MainActor
final class WakeWordManager: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    static let shared = WakeWordManager()

    @Published private(set) var enabled: Bool = UserDefaults.standard.bool(forKey: "jarvis.wake.enabled")
    @Published private(set) var isListening = false
    @Published private(set) var status = "Wake word is off"
    @Published private(set) var liveText = ""
    @Published private(set) var inputRoute = "Not listening"
    @Published private(set) var lastDetected = "Never"

    var onWake: (() -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var restartTask: Task<Void, Never>?
    private var lastWakeDate = Date.distantPast
    private var intentionalStop = false

    override private init() {
        super.init()
        recognizer?.delegate = self

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioRouteChanged),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioInterrupted),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setEnabled(_ newValue: Bool) {
        enabled = newValue
        UserDefaults.standard.set(newValue, forKey: "jarvis.wake.enabled")

        if newValue {
            intentionalStop = false
            Task { await startWithPermissions() }
        } else {
            intentionalStop = true
            stop(deactivateAudio: true)
            status = "Wake word is off"
        }
    }

    func resumeIfNeeded() {
        guard enabled, !isListening else { return }
        intentionalStop = false
        Task { await startWithPermissions() }
    }

    private func startWithPermissions() async {
        guard enabled else { return }

        status = "Requesting microphone permission..."
        let micAllowed = await requestMicrophonePermission()
        guard micAllowed else {
            status = "Microphone permission denied"
            isListening = false
            return
        }

        status = "Requesting speech permission..."
        let speechAllowed = await requestSpeechPermission()
        guard speechAllowed else {
            status = "Speech recognition permission denied"
            isListening = false
            return
        }

        startRecognition()
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func requestSpeechPermission() async -> Bool {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current == .authorized { return true }
        if current == .denied || current == .restricted { return false }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func startRecognition() {
        guard enabled, !intentionalStop else { return }

        stopRecognitionOnly()

        guard let recognizer, recognizer.isAvailable else {
            status = "Speech recognition is unavailable"
            scheduleRestart(after: 2.0)
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetooth, .defaultToSpeaker]
            )
            try session.setActive(true, options: [])
            preferGlassesMicrophone(session)
            updateInputRoute(session)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.contextualStrings = ["Hey Jarvis", "Jarvis"]
            request.taskHint = .dictation
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                status = "Microphone audio format is unavailable"
                scheduleRestart(after: 1.5)
                return
            }

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    self?.handleRecognition(result: result, error: error)
                }
            }

            audioEngine.prepare()
            try audioEngine.start()

            isListening = true
            liveText = ""
            status = "Listening for “Hey Jarvis”"
        } catch {
            isListening = false
            status = "Listener error: \(error.localizedDescription)"
            scheduleRestart(after: 1.5)
        }
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let text = result.bestTranscription.formattedString
            liveText = text

            if containsWakePhrase(text) {
                let now = Date()
                if now.timeIntervalSince(lastWakeDate) > 4.0 {
                    lastWakeDate = now
                    lastDetected = Self.timeFormatter.string(from: now)
                    status = "Hey Jarvis detected ✓"
                    onWake?()

                    // Clear the accumulated transcript so the same phrase does not fire twice.
                    restartRecognition(after: 0.45)
                    return
                }
            }

            if result.isFinal {
                restartRecognition(after: 0.35)
                return
            }
        }

        if error != nil, enabled, !intentionalStop {
            restartRecognition(after: 0.8)
        }
    }

    private func containsWakePhrase(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : " " }
        let clean = String(normalized)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        return clean.contains("hey jarvis")
    }

    private func preferGlassesMicrophone(_ session: AVAudioSession) {
        guard let inputs = session.availableInputs else { return }

        let preferred = inputs.first { input in
            let name = input.portName.lowercased()
            return input.portType == .bluetoothHFP && (
                name.contains("m02") ||
                name.contains("m01") ||
                name.contains("cyan") ||
                name.contains("glasses")
            )
        } ?? inputs.first(where: { $0.portType == .bluetoothHFP })

        if let preferred {
            try? session.setPreferredInput(preferred)
        }
    }

    private func updateInputRoute(_ session: AVAudioSession = .sharedInstance()) {
        if let input = session.currentRoute.inputs.first {
            inputRoute = "\(input.portName) · \(input.portType.rawValue)"
        } else {
            inputRoute = "No audio input"
        }
    }

    private func restartRecognition(after delay: TimeInterval) {
        stopRecognitionOnly()
        scheduleRestart(after: delay)
    }

    private func scheduleRestart(after delay: TimeInterval) {
        restartTask?.cancel()
        guard enabled, !intentionalStop else { return }

        restartTask = Task { [weak self] in
            let nanos = UInt64(max(delay, 0.1) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.enabled, !self.intentionalStop else { return }
                self.startRecognition()
            }
        }
    }

    private func stopRecognitionOnly() {
        restartTask?.cancel()
        restartTask = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    func stop(deactivateAudio: Bool) {
        stopRecognitionOnly()
        liveText = ""
        inputRoute = "Not listening"

        if deactivateAudio {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    @objc private func audioRouteChanged() {
        let session = AVAudioSession.sharedInstance()
        preferGlassesMicrophone(session)
        updateInputRoute(session)
    }

    @objc private func audioInterrupted(_ note: Notification) {
        guard let info = note.userInfo,
              let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }

        switch type {
        case .began:
            status = "Audio interrupted"
            stopRecognitionOnly()
        case .ended:
            if enabled, !intentionalStop {
                status = "Restarting Hey Jarvis..."
                scheduleRestart(after: 0.5)
            }
        @unknown default:
            break
        }
    }

    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if available {
                if self.enabled && !self.isListening { self.scheduleRestart(after: 0.25) }
            } else {
                self.status = "Speech recognizer temporarily unavailable"
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .medium
        return f
    }()
}
