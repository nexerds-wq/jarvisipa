import AVFoundation
import Foundation

@MainActor
final class VoiceSpeaker {
    private var audioPlayer: AVAudioPlayer?
    private let fallback = AVSpeechSynthesizer()

    func speak(_ reply: VoiceReply) async {
        if let audio = reply.audio, let player = try? AVAudioPlayer(data: audio) {
            audioPlayer = player
            player.prepareToPlay()
            player.play()
            while player.isPlaying {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            audioPlayer = nil
            return
        }

        let utterance = AVSpeechUtterance(string: reply.text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.51
        fallback.speak(utterance)
        while fallback.isSpeaking {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
