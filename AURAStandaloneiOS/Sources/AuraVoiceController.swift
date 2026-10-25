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
        Answer quickly. Default to one or two short spoken sentences; only go longer when asked.\n        Start with the answer immediately. Avoid filler, preambles, and unnecessary detail.
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
    @Published var selectedVoice = UserDefaults.standard.string(forKey: "AuraPreferredVoice") ?? "Automatic" {
        didSet { UserDefaults.standard.set(selectedVoice, forKey: "AuraPreferredVoice") }
    }

    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var session: LanguageModelSession?
    private var generationTask: Task<Void, Never>?
    private var hasMicrophoneTap = false
    private var microphoneAuthorized = false
    private var spokenPrefixCount = 0
    private var startedSpeakingReply = false
    private var restartTask: Task<Void, Never>?
    private var didActivateAutomatically = false
    private var silenceTask: Task<Void, Never>?
    private var recognitionCycle: UInt64 = 0
    private var lastSpeechUpdate = Date.distantPast
    private var lastVisibleReplyUpdate = Date.distantPast
    private let musicPlayer = MPMusicPlayerController.systemMusicPlayer

    private lazy var englishVoices: [AVSpeechSynthesisVoice] = {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("en") }
            .sorted { left, right in
                if left.quality.rawValue != right.quality.rawValue {
                    return left.quality.rawValue > right.quality.rawValue
                }
                if (left.language == "en-US") != (right.language == "en-US") {
                    return left.language == "en-US"
                }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
    }()

    var availableVoices: [String] { ["Automatic"] + englishVoices.map(\.identifier) }

    func voiceLabel(for id: String) -> String {
        guard id != "Automatic" else { return "Best installed voice (prefer Premium)" }
        guard let voice = englishVoices.first(where: { $0.identifier == id }) else { return "Unavailable voice" }
        let quality: String
        switch voice.quality {
        case .premium: quality = "Premium"
        case .enhanced: quality = "Enhanced"
        default: quality = "Standard"
        }
        return "\(voice.name) • \(quality) • \(voice.language)"
    }

    override init() {
        super.init()
        synthesizer.delegate = self
        checkAvailability()
    }

    func checkAvailability() {
        switch SystemLanguageModel.default.availability {
        case .available:
            modelReady = true
            if !isListening && !isGenerating { status = handsFree ? "Ready for Hey Jarvis." : "Ready. Say Hey Jarvis or tap the microphone." }
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
        if microphoneAuthorized { startListening(); return }
        SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard authorization == .authorized, granted else {
                        self.status = "Allow Microphone and Speech Recognition in iPhone Settings for JARVIS AURA."
                        return
                    }
                    self.microphoneAuthorized = true
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
        recognitionCycle &+= 1
        let cycle = recognitionCycle
        status = handsFree ? "Listening for Hey Jarvis or Hey AURA..." : "Listening... Tap Finish when done."

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
            try? await Task.sleep(for: .milliseconds(800))
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
        lastVisibleReplyUpdate = .distantPast
        spokenPrefixCount = 0
        startedSpeakingReply = false
        isGenerating = true
        status = "JARVIS is thinking on your iPhone..."

        if session == nil { session = LanguageModelSession(instructions: personality.instructions) }
        guard let currentSession = session else { return }
        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = currentSession.streamResponse(to: prompt)
                var currentResponse = ""
                for try await fragment in stream {
                    currentResponse = fragment.content
                    try Task.checkCancellation()
                    // The local model streams many tiny fragments. Avoid triggering
                    // a full SwiftUI redraw for every fragment on the main actor.
                    let now = Date()
                    if now.timeIntervalSince(self.lastVisibleReplyUpdate) >= 0.12 {
                        self.reply = fragment.content
                        self.lastVisibleReplyUpdate = now
                    }
                    self.speakFirstSentenceWhenReady(from: fragment.content)
                    if self.status != "Responding on-device..." {
                        self.status = "Responding on-device..."
                    }
                }
                self.reply = currentResponse
                self.speakRemainingReply()
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

    // Start talking as soon as the first sentence arrives instead of waiting for
    // the entire local model response. Keep at most two utterances per reply.
    private func speakFirstSentenceWhenReady(from text: String) {
        guard speakReplies, !startedSpeakingReply else { return }
        let chars = Array(text)
        guard let boundary = chars.indices.first(where: { i in
            ".!?".contains(chars[i]) && (i + 1 == chars.count || chars[i + 1].isWhitespace)
        }) else { return }
        let first = String(chars.prefix(boundary + 1))
        guard let utterance = makeUtterance(first) else { return }
        startedSpeakingReply = true
        spokenPrefixCount = boundary + 1
        configureSpeechAudio()
        synthesizer.speak(utterance)
    }

    private func speakRemainingReply() {
        guard speakReplies else { return }
        let chars = Array(reply)
        guard spokenPrefixCount < chars.count else { return }
        let remaining = String(chars.dropFirst(spokenPrefixCount))
        guard let utterance = makeUtterance(remaining) else { return }
        configureSpeechAudio()
        synthesizer.speak(utterance)
    }

    private func makeUtterance(_ text: String) -> AVSpeechUtterance? {
        let spokenText = AuraSpokenText.prepare(text)
        guard !spokenText.isEmpty else { return nil }
        let utterance = AVSpeechUtterance(string: spokenText)
        utterance.voice = (selectedVoice == "Automatic" ? nil : AVSpeechSynthesisVoice(identifier: selectedVoice))
            ?? englishVoices.first
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = personality.rate
        utterance.pitchMultiplier = personality.pitch
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0.08
        return utterance
    }

    private func configureSpeechAudio() {
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .default,
                                  options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers])
            try audio.setActive(true)
        } catch {
            status = "Audio output issue: \(error.localizedDescription)"
        }
    }

    func previewVoice() {
        guard !isGenerating else { return }
        stopMicrophone()
        synthesizer.stopSpeaking(at: .immediate)
        guard let utterance = makeUtterance("Hey, I'm Jarvis. I'm here whenever you need me. What should we do next?") else {
            scheduleRestart()
            return
        }
        configureSpeechAudio()
        status = "Previewing the selected voice..."
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
        let wasHandsFree = handsFree
        interrupt()
        session = nil
        heardText = ""
        reply = ""
        checkAvailability()
        if wasHandsFree { setHandsFree(true) }
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
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self, self.handsFree, !self.isListening, !self.isGenerating else { return }
            self.authorizeMicrophone()
        }
    }

    private func handlePhoneCommand(_ prompt: String) -> Bool {
        let lower = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Local, instant answers: no language-model inference needed.
        if lower.range(of: #"^(hey (jarvis|aura)[, ]*)?(what('?s| is) )?(the )?(current )?time( is it)?[?.! ]*$"#, options: .regularExpression) != nil {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            reply = "It's " + formatter.string(from: Date())
            speakFullReply()
            if !synthesizer.isSpeaking { scheduleRestart() }
            return true
        }
        if lower.range(of: #"^(hey (jarvis|aura)[, ]*)?(what('?s| is) )?(today('?s)? |the )?(date|day)( today| is it)?[?.! ]*$"#, options: .regularExpression) != nil {
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            formatter.timeStyle = .none
            reply = "Today is " + formatter.string(from: Date())
            speakFullReply()
            if !synthesizer.isSpeaking { scheduleRestart() }
            return true
        }
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
