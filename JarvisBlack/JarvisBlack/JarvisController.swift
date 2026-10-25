import Combine
import Foundation

@MainActor
final class JarvisController: ObservableObject {
    private let wake = WakeListener()
    private let music = MusicCommands()
    private let voice = VoiceSpeaker()
    private let backend = VoiceBackend()
    private var history: [ChatLine] = []
    private var launched = false

    func launch() async {
        guard !launched else { return }
        launched = true
        wake.onCommand = { [weak self] phrase in
            Task { await self?.handle(phrase) }
        }
        let permitted = await wake.requestPermissions()
        if permitted {
            wake.start()
        } else {
            await voice.speak(VoiceReply(
                text: "Please allow microphone and speech recognition in Settings to use Jarvis.",
                audio: nil
            ))
        }
    }

    private func handle(_ phrase: String) async {
        if let intent = MusicIntent.parse(phrase) {
            let spoken = await music.execute(intent)
            await voice.speak(await backend.synthesize(spoken))
            wake.start()
            return
        }

        do {
            let reply = try await backend.ask(phrase, history: history)
            history.append(ChatLine(role: "user", content: phrase))
            history.append(ChatLine(role: "assistant", content: reply.text))
            if history.count > 12 { history.removeFirst(history.count - 12) }
            await voice.speak(reply)
        } catch {
            await voice.speak(VoiceReply(
                text: error.localizedDescription == BackendError.notConfigured.localizedDescription
                    ? "The AI server isn't configured yet. Music commands can still work."
                    : "I couldn't reach my AI service. Please check your connection.",
                audio: nil
            ))
        }
        wake.start()
    }
}
