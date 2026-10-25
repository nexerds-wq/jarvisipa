import AVFoundation
import Foundation
import Speech
import UIKit

/// An on-device-first speech-recognition wake phrase listener.
/// iOS can suspend an app or interrupt its audio session; this is not a system-wide hotword.
@MainActor
final class WakeListener {
    var onCommand: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var rotationTask: Task<Void, Never>?
    private var isActive = false
    private var isAwake = false
    private var hasTap = false
    private var generation = 0
    private var command = ""
    private var isInterrupted = false
    private var notificationTokens: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor [weak self] in
                guard let self else { return }
                if value == AVAudioSession.InterruptionType.began.rawValue {
                    self.isInterrupted = true
                    self.tearDownRecognition()
                } else if value == AVAudioSession.InterruptionType.ended.rawValue {
                    self.isInterrupted = false
                    self.scheduleRetry()
                }
            }
        })
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRetry()
            }
        })
        notificationTokens.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRetry()
            }
        })
    }

    private static let wakeExpression = try! NSRegularExpression(
        pattern: #"^\s*(?:(?:hey|hello|hi)[, ]+)?(?:jarvis|jar\s*vis|jervis)\b"#,
        options: [.caseInsensitive]
    )

    func requestPermissions() async -> Bool {
        let microphoneGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        return microphoneGranted && speechGranted
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        isAwake = false
        command = ""
        beginRecognition()
    }

    func stop() {
        isActive = false
        generation += 1
        silenceTask?.cancel()
        rotationTask?.cancel()
        silenceTask = nil
        rotationTask = nil
        tearDownRecognition()
    }

    private func beginRecognition() {
        guard isActive, !isInterrupted else { return }
        tearDownRecognition()
        guard let recognizer, recognizer.isAvailable else {
            scheduleRetry()
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord,
                                    mode: .voiceChat,
                                    options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try session.setActive(true)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            request.contextualStrings = [
                "Hey Jarvis", "Hello Jarvis", "Hi Jarvis", "Jarvis", "Jervis",
                "pause music", "play music"
            ]
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            self.request = request

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            hasTap = true

            generation += 1
            let thisGeneration = generation
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self, self.isActive, self.generation == thisGeneration else { return }
                    if let result {
                        self.processTranscript(result.bestTranscription.formattedString)
                    }
                    if error != nil || result?.isFinal == true {
                        self.scheduleRetry()
                    }
                }
            }

            engine.prepare()
            try engine.start()

            // Short sessions recover more gracefully from recognition service time limits.
            rotationTask?.cancel()
            rotationTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                guard !Task.isCancelled else { return }
                self?.beginRecognition()
            }
        } catch {
            tearDownRecognition()
            scheduleRetry()
        }
    }

    private func processTranscript(_ transcript: String) {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let nsText = text as NSString
        let match = Self.wakeExpression.firstMatch(
            in: text, range: NSRange(location: 0, length: nsText.length)
        )
        if !isAwake {
            guard match != nil else { return }
            isAwake = true
            command = ""
            scheduleSilenceCheck()
        }

        let relevant: String
        if let match {
            let end = match.range.location + match.range.length
            relevant = nsText.substring(from: min(end, nsText.length))
        } else {
            // The recognition session can restart after "Hey Jarvis" was heard.
            relevant = text
        }

        let cleaned = relevant.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned != command {
            command = cleaned
            scheduleSilenceCheck()
        }
    }

    private func scheduleSilenceCheck() {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            guard let self else { return }
            let hasCommand = !self.command.isEmpty
            let wait: UInt64 = hasCommand ? 1_350_000_000 : 7_000_000_000
            try? await Task.sleep(nanoseconds: wait)
            guard !Task.isCancelled, self.isActive, self.isAwake else { return }
            let finalCommand = self.command.trimmingCharacters(in: .whitespacesAndNewlines)
            self.isAwake = false
            self.command = ""
            guard !finalCommand.isEmpty else { return }
            self.stop()
            self.onCommand?(finalCommand)
        }
    }

    private func scheduleRetry() {
        guard isActive, !isInterrupted else { return }
        rotationTask?.cancel()
        rotationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.beginRecognition()
        }
    }

    private func tearDownRecognition() {
        if engine.isRunning { engine.stop() }
        if hasTap {
            engine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        request?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
    }
}
