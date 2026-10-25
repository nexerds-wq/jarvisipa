import Combine
import Foundation

@MainActor
final class JarvisController: ObservableObject {
    private let wake = WakeListener()
    private let music = MusicCommands()
    private let voice = VoiceSpeaker()
    private let backend = VoiceBackend()
    private var launched = false
    private var currentCommand: Task<Void, Never>?
    private var announcedModelLoading = false

    func launch() async {
        guard !launched else { return }
        launched = true
        wake.onWake = { [weak self] in
            guard let self else { return }
            // A short confirmation so the user knows the wake phrase was heard.
            // Do not stop recognition: the next words are the command.
            Task { await self.voice.speak(VoiceReply(text: "Yes?", audio: nil)) }
        }
        wake.onFailure = { message in
            NSLog("[Jarvis WakeListener] %@", message)
        }
        wake.onCommand = { [weak self] phrase in
            guard let self else { return }
            // Re-arm before AI generation or speech: a new wake phrase can
            // interrupt Jarvis even when he is still talking.
            self.wake.start()
            self.currentCommand?.cancel()
            self.voice.stop()
            self.currentCommand = Task { await self.handle(phrase) }
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
            guard !Task.isCancelled else { return }
            await voice.speak(backend.synthesize(spoken))
            return
        }

        do {
            if !backend.isReady && !announcedModelLoading {
                announcedModelLoading = true
                await voice.speak(VoiceReply(
                    text: "Loading my offline AI. The first download can take several minutes.",
                    audio: nil
                ))
                guard !Task.isCancelled else { return }
            }
            let reply = try await backend.ask(phrase)
            guard !Task.isCancelled else { return }
            await voice.speak(reply)
        } catch {
            guard !Task.isCancelled else { return }
            await voice.speak(VoiceReply(
                text: "I couldn't load my offline AI. Please check storage and connect to Wi-Fi for the first model download.",
                audio: nil
            ))
        }
    }
}
