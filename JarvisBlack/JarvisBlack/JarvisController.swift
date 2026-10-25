import Combine
import Foundation

@MainActor
final class JarvisController: ObservableObject {
    private let wake = WakeListener()
    private let music = MusicCommands()
    private let voice = VoiceSpeaker()
    private let backend = VoiceBackend()
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
            await voice.speak(backend.synthesize(spoken))
            wake.start()
            return
        }

        do {
            let reply = try await backend.ask(phrase)
            await voice.speak(reply)
        } catch {
            await voice.speak(VoiceReply(
                text: "I couldn't load my offline AI. Please check storage and connect to Wi-Fi for the first model download.",
                audio: nil
            ))
        }
        wake.start()
    }
}
