import Foundation

/// Wait for both stable recognized words and quiet microphone audio before
/// sending a question. A short pause in a sentence must not cut it in half.
enum JarvisSpeechEndpoint {
    static let transcriptQuietTime: TimeInterval = 1.8
    static let microphoneQuietTime: TimeInterval = 0.9
    static let maximumMeterDelay: TimeInterval = 4.5
    static let patientTranscriptQuietTime: TimeInterval = 2.7
    static let patientMicrophoneQuietTime: TimeInterval = 1.25
    static let patientMaximumMeterDelay: TimeInterval = 6.5

    static func remainingWait(now:Date, lastTranscript:Date, lastVoice:Date,
                              patient:Bool = false) -> TimeInterval {
        let textQuiet = patient ? patientTranscriptQuietTime : transcriptQuietTime
        let micQuiet = patient ? patientMicrophoneQuietTime : microphoneQuietTime
        let maxMeter = patient ? patientMaximumMeterDelay : maximumMeterDelay
        let transcriptAge = max(0,now.timeIntervalSince(lastTranscript))
        let textWait = max(0,textQuiet - transcriptAge)
        // An always-loud fan must not hold a question forever when Speech
        // has stopped producing words. Actual new transcript changes reset it.
        if transcriptAge >= maxMeter { return 0 }
        let voiceAge = max(0,now.timeIntervalSince(lastVoice))
        let micWait = max(0,micQuiet - voiceAge)
        return max(textWait,micWait)
    }

    static func explicitFinishedQuestion(_ speech:String) -> String? {
        let trimmed = speech.trimmingCharacters(in:.whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let cues = ["that's all", "that is all", "i'm done", "i am done",
                    "end of question", "finished talking"]
        for cue in cues {
            guard lower.hasSuffix(cue) else { continue }
            let prefix = String(trimmed.dropLast(cue.count))
                .trimmingCharacters(in:.whitespacesAndNewlines.union(.punctuationCharacters))
            if !prefix.isEmpty { return prefix }
        }
        return nil
    }
}
