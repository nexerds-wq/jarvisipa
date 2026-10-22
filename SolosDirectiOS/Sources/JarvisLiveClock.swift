import Foundation

/// Handles questions whose answers must come from the device clock rather
/// than from an LLM's training data or a possibly outdated saved timestamp.
/// Uses the iPhone's current locale, calendar and time zone on every request.
enum JarvisLiveClock {
    static func answer(for question: String, at instant: Date = Date()) -> String? {
        let normalized = question.lowercased()
            .replacingOccurrences(of: #"[’']"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"^(?:hey\s+)?jarvis(?:\s+|$)"#,
                with: "", options: .regularExpression
            ).trimmingCharacters(in: .whitespacesAndNewlines)

        let bothPatterns = [
            #"^(?:(?:what|whats|what is|tell me|can you tell me|give me|show me)\s+)?(?:the\s+)?(?:(?:current|todays|today)\s+)?(?:time\s+and\s+date|date\s+and\s+time)(?:\s+(?:is it|now|today|please))?$"#
        ]
        let timePatterns = [
            #"^(?:(?:what|whats|what is|tell me|can you tell me|do you know|give me|show me)\s+)?(?:the\s+)?(?:(?:current|local|exact)\s+)?time(?:\s+(?:is it|now|right now|please))?$"#,
            #"^what\s+time\s+is\s+it(?:\s+(?:now|right now))?$"#,
            #"^how\s+late\s+is\s+it(?:\s+now)?$"#,
            #"^time\s+now$"#
        ]
        let datePatterns = [
            #"^(?:(?:what|whats|what is|tell me|can you tell me|give me|show me)\s+)?(?:the\s+)?(?:(?:current|todays|today|exact)\s+)?date(?:\s+(?:today|now|is it|please))?$"#,
            #"^what\s+(?:day|date)\s+is\s+it(?:\s+(?:today|now))?$"#,
            #"^what\s+day\s+is\s+today$"#,
            #"^what\s+day\s+of\s+the\s+week\s+is\s+it(?:\s+today)?$"#,
            #"^(?:whats|what\s+is)\s+today(?:s)?\s+date$"#,
            #"^what\s+is\s+today$"#
        ]
        let yearPatterns = [
            #"^(?:what|whats|what\s+is|tell\s+me|can\s+you\s+tell\s+me)\s+(?:the\s+)?(?:current\s+)?year(?:\s+is\s+it)?$"#,
            #"^what\s+year\s+are\s+we\s+in$"#
        ]
        let monthPatterns = [
            #"^(?:what|whats|what\s+is|tell\s+me)\s+(?:the\s+)?(?:current\s+)?month(?:\s+is\s+it)?$"#
        ]

        // Rules are anchored, so "what time did the game start?" still goes
        // to the AI and is not mistaken for a live-clock question.
        let kind: String
        if matches(normalized, bothPatterns) {
            kind = "both"
        } else if matches(normalized, timePatterns) {
            kind = "time"
        } else if matches(normalized, datePatterns) {
            kind = "date"
        } else if matches(normalized, yearPatterns) {
            kind = "year"
        } else if matches(normalized, monthPatterns) {
            kind = "month"
        } else {
            return nil
        }

        let timeFormatter = DateFormatter()
        timeFormatter.locale = .autoupdatingCurrent
        timeFormatter.calendar = .autoupdatingCurrent
        timeFormatter.timeZone = .autoupdatingCurrent
        timeFormatter.timeStyle = .short

        let dateFormatter = DateFormatter()
        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.calendar = .autoupdatingCurrent
        dateFormatter.timeZone = .autoupdatingCurrent
        dateFormatter.dateStyle = .full

        let time = timeFormatter.string(from: instant)
        let date = dateFormatter.string(from: instant)
        switch kind {
        case "both":
            return "It's \(time). Today is \(date)."
        case "time":
            return "It's \(time)."
        case "date":
            return "Today is \(date)."
        case "year":
            return "The year is \(Calendar.autoupdatingCurrent.component(.year, from: instant))."
        case "month":
            let formatter = DateFormatter()
            formatter.locale = .autoupdatingCurrent
            formatter.calendar = .autoupdatingCurrent
            formatter.timeZone = .autoupdatingCurrent
            formatter.dateFormat = "LLLL"
            return "It's \(formatter.string(from: instant))."
        default:
            return nil
        }
    }

    static func modelTimeContext(at instant: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a zzz"
        return "The live iPhone date and time at this request is \(formatter.string(from: instant)). Use this value when a question depends on today's date. Do not invent fresh news or current external information."
    }

    private static func matches(_ text: String, _ patterns: [String]) -> Bool {
        patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }
}
