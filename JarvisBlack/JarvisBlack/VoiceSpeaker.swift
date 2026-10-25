import AVFoundation
import Foundation

/// An actual AVSpeechSynthesizer delegate is necessary: `isSpeaking` can still
/// be false immediately after `speak`, before iOS starts the utterance.
@MainActor
final class VoiceSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var completion: CheckedContinuation<Void, Never>?
    private var currentUtterance: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }

    func speak(_ reply: VoiceReply) async {
        stop()
        if let data = reply.audio, let player = try? AVAudioPlayer(data: data) {
            audioPlayer = player
            player.prepareToPlay()
            if player.play() {
                while player.isPlaying && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                audioPlayer = nil
                return
            }
        }

        let text = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !Task.isCancelled else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.49
        utterance.volume = 1.0
        currentUtterance = utterance

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                completion = continuation
                synthesizer.speak(utterance)
            }
        } onCancel: {
            Task { @MainActor in self.stop() }
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        currentUtterance = nil
        finish()
    }

    private func finish() {
        let waiting = completion
        completion = nil
        waiting?.resume()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard currentUtterance === utterance else { return }
        currentUtterance = nil
        finish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard currentUtterance === utterance else { return }
        currentUtterance = nil
        finish()
    }
}
