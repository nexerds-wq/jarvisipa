import AVFoundation
import Foundation
import FoundationModels
import Speech
import MediaPlayer
import UIKit
import SwiftUI

enum AuraPersonality: String, CaseIterable, Identifiable {
    case warm = "Warm"
    case natural = "Natural"
    case expressive = "Expressive"

    var id: String { rawValue }

    var instructions: String {
        let base = """
        You are JARVIS, a thoughtful and emotionally responsive voice companion.
        You're having a real spoken conversation. Be warm, perceptive, honest, and natural.
        Match the other person's emotional tone. Listen to sadness with empathy, respond
        to excitement with energy, and use gentle humor when appropriate. Don't claim
        you have human feelings or real-world abilities you don't possess.
        Speak in everyday conversational English with contractions and varied sentence
        length. Don't use markdown, emojis, numbered lists, asterisks, or stage directions.
        Usually answer in two to five spoken sentences, but go deeper when the person asks.
        Ask relevant follow-up questions sometimes. If unsure, say so honestly.
        You have no internet, no external tools, no ability to control devices, and no
        knowledge of events after your on-device model's training data.
        """
        switch self {
        case .warm: return base + "\nBe especially gentle, reassuring, patient, and encouraging."
        case .natural: return base + "\nBe grounded, casual, thoughtful, and unforced."
        case .expressive: return base + "\nBe lively, curious, quick-witted, and vivid without sounding theatrical."
        }
    }

    var pitch: Float {
        switch self {
        case .warm: return 1.02
        case .natural: return 1.0
        case .expressive: return 1.09
        }
    }

    var rate: Float {
        switch self {
        case .warm: return 0.48
        case .natural: return 0.52
        case .expressive: return 0.55
        }
    }
}

@MainActor
final class AuraVoiceController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var status = "Checking the on-device AI model..."
    @Published var modelReady = false
    @Published var isListening = false
    @Published var isGenerating = false
    @Published var heardText = ""
    @Published var reply = ""
    @Published var personality: AuraPersonality = .natural
    @Published var speakReplies = true
    @Published var handsFree = false
    @Published var selectedVoice = "Automatic"

    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var session: LanguageModelSession?
    private var generationTask: Task<Void, Never>?
    private var spokenCharacters = 0
    private var hasMicrophoneTap = false
    private var restartTask: Task<Void, Never>?
    private var didActivateAutomatically = false
    private var silenceTask: Task<Void, Never>?
    private var recognitionCycle: UInt64 = 0
    private var lastSpeechUpdate = Date.distantPast
    private let musicPlayer = MPMusicPlayerController.systemMusicPlayer

    var availableVoices: [String] { ["Automatic"] + AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }.map { $0.identifier }.sorted() }

    override init() {
        super.init()
        synthesizer.delegate = self
        checkAvailability()
    }

    func checkAvailability() {
        switch SystemLanguageModel.default.availability {
        case .available:
            modelReady = true
            if !isListening && !isGenerating { status = "Ready. Tap the microphone and talk naturally." }
        case .unavailable:
            modelReady = false
            status = "Apple Intelligence isn't ready. Update to iOS 26+, enable Apple Intelligence in Settings, allow its download, then tap Check."
        @unknown default:
            modelReady = false
            status = "The on-device model isn't available yet. Check Apple Intelligence settings."
        }
    }

    func microphoneTapped() {
        if isListening {
            finishListeningAndRespond()
        } else {
            authorizeMicrophone()
        }
    }

    private func authorizeMicrophone() {
        guard modelReady, !isGenerating else { return }
        SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard authorization == .authorized, granted else {
                        self.status = "Allow Microphone and Speech Recognition in iPhone Settings for JARVIS AURA."
                        return
                    }
                    self.startListening()
                }
            }
        }
    }

    private func startListening() {
        guard let recognizer else {
            status = "English speech recognition isn't available on this iPhone. You can still type."
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            status = "Offline English speech recognition isn't available right now. You can still type to JARVIS."
            return
        }

        synthesizer.stopSpeaking(at: .immediate)
        stopMicrophone()
        heardText = ""
        status = "Listening on this iPhone... Tap Finish when you're done."

        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .default,
                                  options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try audio.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            request.taskHint = .dictation
            recognitionRequest = request

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self, self.isListening else { return }
                    if let result {
                        let incoming = result.bestTranscription.formattedString
                        if incoming != self.heardText {
                            self.heardText = incoming
                            self.lastSpeechUpdate = Date()
                            if self.handsFree { self.scheduleSilenceFinish(cycle: cycle) }
                        }
                        if self.handsFree && result.isFinal { self.finishListeningAndRespond() }
                    }
                    if let error {
                        self.status = "Listening ended: \(error.localizedDescription). Tap to try again."
                        self.stopMicrophone()
                        self.scheduleRestart()
                    }
                }
            }

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw NSError(domain: "AURA", code: 1, userInfo: [NSLocalizedDescriptionKey: "No working microphone input was found."])
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            hasMicrophoneTap = true
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            if handsFree {
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(48))
                    guard let self, self.isListening, self.recognitionCycle == cycle else { return }
                    self.finishListeningAndRespond()
                }
            }
        } catch {
            stopMicrophone()
            status = "Couldn't start the mic: \(error.localizedDescription)"
        }
    }

    private func finishListeningAndRespond() {
        let text = heardText.trimmingCharacters(in: .whitespacesAndNewlines)
        stopMicrophone()
        if text.isEmpty {
            status = "I didn't catch anything."
            scheduleRestart()
        } else if handsFree && !text.lowercased().contains("hey aura") && !text.lowercased().contains("hey jarvis") {
            status = "Listening for Hey AURA or Hey Jarvis..."
            scheduleRestart()
        } else {
            let cleaned = text.replacingOccurrences(of: "(?i)hey (aura|jarvis)[, ]*", with: "", options: .regularExpression)
            send(cleaned.isEmpty ? "Hello" : cleaned)
        }
    }

    private func scheduleSilenceFinish(cycle: UInt64) {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self, self.isListening, self.recognitionCycle == cycle else { return }
            let phrase = self.heardText.lowercased()
            if phrase.contains("hey aura") || phrase.contains("hey jarvis") {
                self.finishListeningAndRespond()
            }
        }
    }

    private func stopMicrophone() {
        silenceTask?.cancel()
        silenceTask = nil
        recognitionCycle &+= 1
        if audioEngine.isRunning { audioEngine.stop() }
        if hasMicrophoneTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasMicrophoneTap = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false
    }

    func send(_ message: String) {
        let prompt = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isGenerating else { return }
        guard modelReady else { checkAvailability(); return }
        stopMicrophone()
        synthesizer.stopSpeaking(at: .immediate)
        generationTask?.cancel()
        if handlePhoneCommand(prompt) { scheduleRestart(); return }
        heardText = prompt
        reply = ""
        spokenCharacters = 0
        isGenerating = true
        status = "JARVIS is thinking on your iPhone..."

        if session == nil { session = LanguageModelSession(instructions: personality.instructions) }
        guard let currentSession = session else { return }
        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = currentSession.streamResponse(to: prompt)
                for try await fragment in stream {
                    try Task.checkCancellation()
                    self.reply = fragment.content
                    self.speakCompletedPhrases(final: false)
                    self.status = "Responding on-device..."
                }
                self.speakCompletedPhrases(final: true)
                self.isGenerating = false
                self.status = self.synthesizer.isSpeaking ? "JARVIS is speaking..." : "Ready for another question."
                if !self.synthesizer.isSpeaking { self.scheduleRestart() }
            } catch is CancellationError {
                self.isGenerating = false
                self.status = "Interrupted. Ready when you are."
            } catch {
                self.isGenerating = false
                self.status = "The on-device AI couldn't finish: \(error.localizedDescription)"
                if self.reply.isEmpty { self.reply = "Sorry, something interrupted that response. Please try again." }
                // A new session clears excessive context or a failed generation.
                self.session = nil
                self.scheduleRestart()
            }
        }
    }

    private func speakCompletedPhrases(final: Bool) {
        guard speakReplies else { return }
        if spokenCharacters > reply.count { spokenCharacters = reply.count }
        let pending = String(reply.dropFirst(spokenCharacters))
        guard !pending.isEmpty else { return }

        var completedLength = 0
        let characters = Array(pending)
        for index in characters.indices {
            let char = characters[index]
            if ".!?".contains(char) && (index == characters.count - 1 || characters[index + 1].isWhitespace) {
                completedLength = index + 1
            }
        }
        if final { completedLength = characters.count }
        if completedLength == 0 { return }

        let phrase = String(characters.prefix(completedLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        spokenCharacters += completedLength
        guard !phrase.isEmpty else { return }

        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
            try audio.setActive(true)
        } catch {
            status = "Audio output issue: \(error.localizedDescription)"
        }

        let utterance = AVSpeechUtterance(string: phrase)
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix("en") }
        utterance.voice = (selectedVoice == "Automatic" ? nil : AVSpeechSynthesisVoice(identifier: selectedVoice))
            ?? voices.sorted { $0.quality.rawValue > $1.quality.rawValue }.first
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = personality.rate
        utterance.pitchMultiplier = personality.pitch
        utterance.postUtteranceDelay = 0
        synthesizer.speak(utterance)
    }

    func interrupt() {
        generationTask?.cancel()
        generationTask = nil
        restartTask?.cancel()
        handsFree = false
        stopMicrophone()
        synthesizer.stopSpeaking(at: .immediate)
        isGenerating = false
        status = "Stopped. Tap the microphone whenever you're ready."
    }

    func newConversation() {
        interrupt()
        session = nil
        heardText = ""
        reply = ""
        spokenCharacters = 0
        checkAvailability()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if !isGenerating && !synthesizer.isSpeaking && !isListening {
            status = "Ready for another question."
            scheduleRestart()
        }
    }

    func activateAlwaysReady() {
        guard !didActivateAutomatically else { return }
        didActivateAutomatically = true
        setHandsFree(true)
    }

    func setHandsFree(_ enabled: Bool) {
        handsFree = enabled
        restartTask?.cancel()
        if enabled { authorizeMicrophone() } else { stopMicrophone() }
    }

    private func scheduleRestart() {
        guard handsFree, !isListening, !isGenerating, !synthesizer.isSpeaking else { return }
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self, self.handsFree, !self.isListening, !self.isGenerating else { return }
            self.authorizeMicrophone()
        }
    }

    private func handlePhoneCommand(_ prompt: String) -> Bool {
        let lower = prompt.lowercased()
        if lower.contains("pause music") || lower.contains("stop music") { musicPlayer.pause(); reply = "Music paused."; return true }
        if lower.contains("next song") || lower.contains("skip song") { musicPlayer.skipToNextItem(); reply = "Skipping."; return true }
        if lower.contains("previous song") { musicPlayer.skipToPreviousItem(); reply = "Going back."; return true }
        if lower.contains("play music") || lower.contains("resume music") { musicPlayer.play(); reply = "Playing your music."; return true }
        if lower.contains("alarm") && (lower.contains("set") || lower.contains("open") || lower.contains("create")) {
            reply = "Opening Clock so you can set your alarm. iOS does not let this app directly create Clock alarms."
            if let url = URL(string: "clock-alarm://") { UIApplication.shared.open(url) }
            return true
        }
        return false
    }
}
