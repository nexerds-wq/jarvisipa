import Foundation

/// Language-aware speaking cues, not microphone-based emotion detection.
/// Keep entire sentences intact so AVSpeechSynthesizer can pronounce phrases
/// naturally instead of pausing awkwardly between individual words.
enum JarvisSpeechPerformance {
    enum Tone: String {
        case natural, reassuring, upbeat, playful, urgent
    }

    struct Beat {
        let text: String
        let tone: Tone
    }

    static func beats(for response:String, expressive:Bool = true) -> [Beat] {
        let clean = response.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        guard expressive else { return [Beat(text:clean,tone:.natural)] }
        var pieces: [String] = []
        clean.enumerateSubstrings(in:clean.startIndex..<clean.endIndex,
                                  options:.bySentences) { sentence,_,_,_ in
            let text = (sentence ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
            if !text.isEmpty { pieces.append(text) }
        }
        if pieces.isEmpty { pieces = [clean] }
        // Avoid excessive mini-utterances: the entire sentence is a single beat.
        return pieces.map { Beat(text:$0,tone:tone(for:$0)) }
    }

    static func tone(for sentence:String) -> Tone {
        let text = sentence.lowercased()
        let urgent = ["emergency", "call 911", "call emergency", "immediate danger",
                      "get to safety", "evacuate", "right now", "seek help now"]
        if urgent.contains(where:text.contains) { return .urgent }
        let gentle = ["i'm sorry", "i am sorry", "that sounds hard", "you're not alone",
                      "take a breath", "it's okay", "i hear you", "that must be",
                      "i understand", "here with you", "one step at a time"]
        if gentle.contains(where:text.contains) { return .reassuring }
        let playful = ["haha", "just kidding", "plot twist", "you got me",
                       "classic jarvis", "that's a good one"]
        if playful.contains(where:text.contains) { return .playful }
        let upbeat = ["congratulations", "great news", "well done", "you did it",
                      "awesome", "fantastic", "let's go"]
        if upbeat.contains(where:text.contains) || sentence.hasSuffix("!") { return .upbeat }
        return .natural
    }

    static func adjustments(for tone:Tone, intensity:Double) -> (rate:Double,pitch:Double,pause:Double) {
        let strength = min(1.0,max(0.0,intensity))
        switch tone {
        case .natural: return (0,0,0.025)
        case .reassuring: return (-0.038 * strength,-0.055 * strength,0.10)
        case .upbeat: return (0.035 * strength,0.085 * strength,0.035)
        case .playful: return (0.018 * strength,0.065 * strength,0.055)
        case .urgent: return (-0.012 * strength,-0.015 * strength,0.055)
        }
    }
}
