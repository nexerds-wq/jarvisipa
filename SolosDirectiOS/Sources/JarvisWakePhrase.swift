import Foundation

/// Pure text parsing, separate from microphone and TTS lifecycles.
/// An empty remainder means a valid wake phrase without a question yet.
enum JarvisWakePhrase {
    static func question(afterWakeIn transcript: String) -> String? {
        guard let wake = transcript.range(of:#"\bhey[\s,]+jarvis\b"#,
                                          options:[.regularExpression,.caseInsensitive]) else {
            return nil
        }
        return String(transcript[wake.upperBound...]).trimmingCharacters(
            in:.whitespacesAndNewlines.union(.punctuationCharacters))
    }
}
