import AVFoundation
import Foundation
import FoundationModels
import Speech
import MediaPlayer
import UIKit
import SwiftUI

// AVAudioEngine's tap runs on an audio thread. This bridge swaps speech requests
// without tearing down the input hardware between recognition cycles.
private final class AuraAudioBridge {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func setRequest(_ next: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        request = next
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        request?.append(buffer)
        lock.unlock()
    }
}

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
        Answer quickly. Default to one or two short spoken sentences; only go longer when asked.
        Start with the answer immediately. Avoid filler, preambles, and unnecessary detail.
        Be emotionally perceptive: respond with more tenderness if the person is sad,
        more energy if they are excited, and quiet seriousness for safety concerns.
        Avoid canned reassurances; sound like an engaged, spontaneous companion.
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
    @Published var weatherChimes = UserDefaults.standard.bool(forKey: "AuraWeatherChimes") {
        didSet { UserDefaults.standard.set(weatherChimes, forKey: "AuraWeatherChimes"); configureNearbyAlerts() }
    }
    @Published var localNewsChimes = UserDefaults.standard.bool(forKey: "AuraNewsChimes") {
        didSet { UserDefaults.standard.set(localNewsChimes, forKey: "AuraNewsChimes"); configureNearbyAlerts() }
    }
    @Published private(set) var localAlertStatus = "Optional local alerts are off."
    @Published var handsFree = false
    @Published private(set) var followUpReady = false
    @Published var selectedVoice = UserDefaults.standard.string(forKey: "AuraPreferredVoice") ?? "Automatic" {
        didSet { UserDefaults.standard.set(selectedVoice, forKey: "AuraPreferredVoice") }
    }

    private let audioEngine = AVAudioEngine()
    private let audioBridge = AuraAudioBridge()
    private let synthesizer = AVSpeechSynthesizer()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var session: LanguageModelSession?
    private var generationTask: Task<Void, Never>?
    private var hasMicrophoneTap = false
    private var microphoneAuthorized = false
    private var consecutiveMicFailures = 0
    private var spokenPrefixCount = 0
    private var startedSpeakingReply = false
    private var queuedSpeechCount = 0
    private var restartTask: Task<Void, Never>?
    private var didActivateAutomatically = false
    private var silenceTask: Task<Void, Never>?
    private var followUpExpiryTask: Task<Void, Never>?
    private var recognitionCycle: UInt64 = 0
    private var lastSpeechUpdate = Date.distantPast
    private var lastVisibleReplyUpdate = Date.distantPast
    private let musicPlayer = MPMusicPlayerController.systemMusicPlayer
    private var pendingNearbyChime: String?
    private lazy var nearbyMonitor: AuraNearbyMonitor = {
        let monitor = AuraNearbyMonitor()
        monitor.onChime = { [weak self] message in self?.receiveNearbyChime(message) }
        monitor.onStatus = { [weak self] message in self?.localAlertStatus = message }
        return monitor
    }()

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
        NotificationCenter.default.addObserver(self, selector: #selector(audioSessionInterrupted(_:)),
            name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
        NotificationCenter.default.addObserver(self, selector: #selector(audioRouteChanged(_:)),
            name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance())
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
            // A manual tap sends the current transcript even without the wake word.
            finishListeningAndRespond(manual: true)
        } else {
            authorizeMicrophone()
        }
    }

    private func authorizeMicrophone() {
        guard modelReady, !isGenerating else { return }
        guard queuedSpeechCount == 0, !synthesizer.isSpeaking else { return }
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

    private func ensureAudioInput() throws {
        if audioEngine.isRunning { return }
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .default,
                              options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
        try audio.setActive(true)

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "AURA", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No valid iPhone microphone input is available."
            ])
        }
        if !hasMicrophoneTap {
            let bridge = audioBridge
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                bridge.append(buffer)
            }
            hasMicrophoneTap = true
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func startListening() {
        guard !isGenerating, queuedSpeechCount == 0, !synthesizer.isSpeaking else { return }
        guard !isListening else { return }
        guard let recognizer, recognizer.isAvailable else {
            status = "Speech recognition isn't available. I'll retry automatically."
            consecutiveMicFailures += 1
            scheduleRestart()
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            status = "Offline English recognition isn't installed. Check Dictation in Settings."
            return
        }

        stopRecognition()
        heardText = ""
        recognitionCycle &+= 1
        let cycle = recognitionCycle
        do {
            try ensureAudioInput()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            request.taskHint = .dictation
            recognitionRequest = request
            audioBridge.setRequest(request)
            isListening = true
            status = handsFree
                ? (followUpReady ? "Conversation open. Talk naturally..." : "Listening for Hey Jarvis...")
                : "Listening... Tap to send."

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self, self.isListening, self.recognitionCycle == cycle else { return }
                    if let result {
                        let incoming = result.bestTranscription.formattedString
                        if incoming != self.heardText {
                            self.heardText = incoming
                            self.lastSpeechUpdate = Date()
                            if self.handsFree && self.shouldAccept(incoming) {
                                self.followUpExpiryTask?.cancel()
                                self.scheduleSilenceFinish(cycle: cycle)
                            }
                        }
                        if result.isFinal {
                            if self.shouldAccept(self.heardText) {
                                self.finishListeningAndRespond()
                            } else {
                                self.startNewRecognitionCycle()
                            }
                            return
                        }
                    }
                    if let error {
                        self.consecutiveMicFailures += 1
                        self.status = "Speech recognition renewing: \(error.localizedDescription)"
                        self.stopRecognition()
                        self.scheduleRestart()
                    }
                }
            }
            consecutiveMicFailures = 0

            // iOS limits individual recognition tasks. Renew the recognizer while
            // retaining the already-running microphone engine and audio tap.
            if handsFree {
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(48))
                    guard let self, self.isListening, self.recognitionCycle == cycle else { return }
                    if self.shouldAccept(self.heardText) {
                        self.finishListeningAndRespond()
                    } else {
                        self.startNewRecognitionCycle()
                    }
                }
            }
        } catch {
            stopRecognition()
            stopAudioInput()
            consecutiveMicFailures += 1
            status = "Microphone retrying: \(error.localizedDescription)"
            scheduleRestart()
        }
    }

    private func shouldAccept(_ text: String) -> Bool {
        if !handsFree { return true }
        let words = text.lowercased()
        return followUpReady ||
            words.contains("hey jarvis") || words.contains("hey aura")
    }

    private func startNewRecognitionCycle() {
        stopRecognition()
        if handsFree { scheduleRestart() }
    }

    private func finishListeningAndRespond(manual: Bool = false) {
        let text = heardText.trimmingCharacters(in: .whitespacesAndNewlines)
        let accepted = manual || shouldAccept(text)
        stopRecognition()
        if text.isEmpty || !accepted {
            status = "Listening for Hey Jarvis..."
            scheduleRestart()
            return
        }
        followUpExpiryTask?.cancel()
        followUpReady = false
        let cleaned = text.replacingOccurrences(
            of: "(?i)hey (aura|jarvis)[, ]*", with: "", options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        send(cleaned.isEmpty ? "Hello" : cleaned)
    }

    private func scheduleSilenceFinish(cycle: UInt64) {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1350))
            guard !Task.isCancelled, let self, self.isListening,
                  self.recognitionCycle == cycle else { return }
            if self.shouldAccept(self.heardText) { self.finishListeningAndRespond() }
        }
    }

    private func stopRecognition() {
        silenceTask?.cancel()
        silenceTask = nil
        recognitionCycle &+= 1
        // Stop feeding the current request before ending/canceling it.
        audioBridge.setRequest(nil)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false
    }

    private func stopAudioInput() {
        audioBridge.setRequest(nil)
        if audioEngine.isRunning { audioEngine.stop() }
        if hasMicrophoneTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasMicrophoneTap = false
        }
    }

    private func stopMicrophone() {
        stopRecognition()
        if !handsFree { stopAudioInput() }
    }

    private func openFollowUpWindow() {
        guard handsFree else { return }
        followUpExpiryTask?.cancel()
        followUpReady = true
        scheduleRestart()
        followUpExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self else { return }
            self.followUpReady = false
            if self.isListening {
                self.status = "Listening for Hey Jarvis..."
            }
        }
    }

    @objc private func audioSessionInterrupted(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began {
            stopRecognition()
            stopAudioInput()
            status = "Audio interrupted. Listening will resume when iOS allows it."
        } else if handsFree {
            scheduleRestart()
        }
    }

    @objc private func audioRouteChanged(_ notification: Notification) {
        guard handsFree, audioEngine.isRunning == false else { return }
        stopRecognition()
        stopAudioInput()
        scheduleRestart()
    }

    func send(_ message: String) {
        let prompt = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isGenerating else { return }
        guard modelReady else { checkAvailability(); return }
        stopMicrophone()
        followUpExpiryTask?.cancel()
        followUpReady = false
        synthesizer.stopSpeaking(at: .immediate)
        queuedSpeechCount = 0
        generationTask?.cancel()
        if handlePhoneCommand(prompt) { if queuedSpeechCount == 0 { openFollowUpWindow() }; return }
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
                if self.queuedSpeechCount == 0 && !self.synthesizer.isSpeaking {
                    if !self.announcePendingNearbyChime() { self.openFollowUpWindow() }
                }
            } catch is CancellationError {
                self.isGenerating = false
                self.status = "Interrupted. Ready when you are."
            } catch {
                self.isGenerating = false
                self.status = "The on-device AI couldn't finish: \(error.localizedDescription)"
                if self.reply.isEmpty { self.reply = "Sorry, something interrupted that response. Please try again." }
                // A new session clears excessive context or a failed generation.
                self.session = nil
                self.openFollowUpWindow()
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
        queuedSpeechCount += 1
        synthesizer.speak(utterance)
    }

    private func speakRemainingReply() {
        guard speakReplies else { return }
        let chars = Array(reply)
        guard spokenPrefixCount < chars.count else { return }
        let remaining = String(chars.dropFirst(spokenPrefixCount))
        guard let utterance = makeUtterance(remaining) else { return }
        if queuedSpeechCount == 0 { configureSpeechAudio() }
        queuedSpeechCount += 1
        synthesizer.speak(utterance)
    }

    private func makeUtterance(_ text: String) -> AVSpeechUtterance? {
        let spokenText = AuraSpokenText.prepare(text)
        guard !spokenText.isEmpty else { return nil }
        let utterance = AVSpeechUtterance(string: spokenText)
        utterance.voice = (selectedVoice == "Automatic" ? nil : AVSpeechSynthesisVoice(identifier: selectedVoice))
            ?? englishVoices.first
            ?? AVSpeechSynthesisVoice(language: "en-US")
        // Light prosody shifts can soften sensitive responses; built-in iOS TTS
        // still cannot provide fully generative human emotional delivery.
        let sensitive = text.lowercased().contains("i'm sorry") ||
            text.lowercased().contains("that sounds hard") ||
            text.lowercased().contains("i hear you")
        utterance.rate = sensitive ? max(0.44, personality.rate - 0.035) : personality.rate
        utterance.pitchMultiplier = sensitive ? max(0.96, personality.pitch - 0.025) : personality.pitch
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0.08
        return utterance
    }

    private func configureSpeechAudio() {
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .default,
                                  options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
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
        queuedSpeechCount = 1
        synthesizer.speak(utterance)
    }

    func interrupt() {
        generationTask?.cancel()
        generationTask = nil
        restartTask?.cancel()
        handsFree = false
        stopMicrophone()
        synthesizer.stopSpeaking(at: .immediate)
        queuedSpeechCount = 0
        followUpExpiryTask?.cancel()
        followUpReady = false
        stopAudioInput()
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
        queuedSpeechCount = max(0, queuedSpeechCount - 1)
        if queuedSpeechCount == 0 && !isGenerating && !isListening {
            status = "Ready for another question."
            if !announcePendingNearbyChime() { openFollowUpWindow() }
        }
    }

    func activateAlwaysReady() {
        guard !didActivateAutomatically else { return }
        didActivateAutomatically = true
        setHandsFree(true)
        configureNearbyAlerts()
    }

    private func configureNearbyAlerts() {
        // Only begins location requests after the user explicitly enables alerts.
        nearbyMonitor.configure(weather: weatherChimes, news: localNewsChimes)
    }

    private func receiveNearbyChime(_ message: String) {
        if !speakReplies { localAlertStatus = message; return }
        if isGenerating || queuedSpeechCount > 0 || (isListening && (followUpReady || !heardText.isEmpty)) {
            pendingNearbyChime = message
        } else {
            announceNearbyChime(message)
        }
    }

    private func announceNearbyChime(_ message: String) {
        stopRecognition() // Retain live microphone input; never interrupt music output.
        followUpExpiryTask?.cancel()
        followUpReady = false
        reply = message
        spokenPrefixCount = 0
        queuedSpeechCount = 0
        speakRemainingReply()
        if queuedSpeechCount == 0 { openFollowUpWindow() }
    }

    private func announcePendingNearbyChime() -> Bool {
        guard let message = pendingNearbyChime, !isGenerating else { return false }
        pendingNearbyChime = nil
        announceNearbyChime(message)
        return true
    }

    func setHandsFree(_ enabled: Bool) {
        handsFree = enabled
        restartTask?.cancel()
        if enabled {
            consecutiveMicFailures = 0
            authorizeMicrophone()
        } else {
            followUpExpiryTask?.cancel()
            followUpReady = false
            stopRecognition()
            stopAudioInput()
        }
    }

    private func scheduleRestart() {
        guard handsFree, !isListening, !isGenerating, queuedSpeechCount == 0, !synthesizer.isSpeaking else { return }
        restartTask?.cancel()
        let retryDelay = consecutiveMicFailures == 0 ? 120 : min(4000, 250 * (1 << min(consecutiveMicFailures, 4)))
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(retryDelay))
            guard !Task.isCancelled, let self, self.handsFree, !self.isListening, !self.isGenerating, self.queuedSpeechCount == 0, !self.synthesizer.isSpeaking else { return }
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
            speakRemainingReply()
            if !synthesizer.isSpeaking { scheduleRestart() }
            return true
        }
        if lower.range(of: #"^(hey (jarvis|aura)[, ]*)?(what('?s| is) )?(today('?s)? |the )?(date|day)( today| is it)?[?.! ]*$"#, options: .regularExpression) != nil {
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            formatter.timeStyle = .none
            reply = "Today is " + formatter.string(from: Date())
            speakRemainingReply()
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
