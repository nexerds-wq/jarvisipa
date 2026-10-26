import Foundation

/// Wait for both stable recognized words and quiet microphone audio before
/// sending a question. A short pause in a sentence must not cut it in half.
enum JarvisSpeechEndpoint {
    static let transcriptQuietTime: TimeInterval = 1.8
    static let microphoneQuietTime: TimeInterval = 0.9
    static let maximumMeterDelay: TimeInterval = 4.5

    static func remainingWait(now:Date, lastTranscript:Date, lastVoice:Date) -> TimeInterval {
        let transcriptAge = max(0,now.timeIntervalSince(lastTranscript))
        let textWait = max(0,transcriptQuietTime - transcriptAge)
        // An always-loud fan must not hold a question forever when Speech
        // has stopped producing words. Actual new transcript changes reset it.
        if transcriptAge >= maximumMeterDelay { return 0 }
        let voiceAge = max(0,now.timeIntervalSince(lastVoice))
        let micWait = max(0,microphoneQuietTime - voiceAge)
        return max(textWait,micWait)
    }
}
