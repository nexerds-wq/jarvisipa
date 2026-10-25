import Foundation

/// Prepares AI-generated text for iPhone speech. The on-screen reply is
/// untouched; only this cleaned text is sent to AVSpeechSynthesizer.
enum AuraSpokenText {
    static func prepare(_ text: String) -> String {
        var cleaned = text
            .replacingOccurrences(of: "(?s)```.*?```", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\[([^\\]]+)\\]\\((?:https?://|www\\.)[^)]+\\)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "(?:https?://|www\\.)\\S+", with: " a link ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: " and ", options: [.caseInsensitive])
            .replacingOccurrences(of: "&quot;", with: " ", options: [.caseInsensitive])

        let chars = Array(cleaned)
        var words = String()
        words.reserveCapacity(cleaned.count)

        for index in chars.indices {
            let char = chars[index]
            let previous = index > 0 ? chars[index - 1] : nil
            let next = index + 1 < chars.count ? chars[index + 1] : nil

            // Preserve contractions and possessives: I'm, don't, Jarvis's.
            if char == "'" || char == "’" {
                if previous?.isLetter == true && next?.isLetter == true {
                    words.append("'")
                } else {
                    words.append(" ")
                }
                continue
            }
            // Preserve decimal numbers such as 3.14.
            if char == ".", previous?.isNumber == true, next?.isNumber == true {
                words.append(char)
                continue
            }
            // Convert 1,200 to 1200 without destroying the number.
            if char == ",", previous?.isNumber == true {
                let following = chars.dropFirst(index + 1).prefix(4)
                if following.prefix(3).count == 3,
                   following.prefix(3).allSatisfy(\.isNumber),
                   (following.count == 3 || !following[following.index(following.startIndex, offsetBy: 3)].isNumber) {
                    continue
                }
            }
            if char == "&" { words.append(" and "); continue }
            if char == "%" { words.append(" percent "); continue }
            if char == "°" { words.append(" degrees "); continue }
            if char == "\n" || char == "\t" { words.append(" "); continue }
            if char.unicodeScalars.contains(where: {
                CharacterSet.punctuationCharacters.contains($0) ||
                CharacterSet.symbols.contains($0) ||
                $0.properties.isEmojiPresentation
            }) {
                words.append(" ")
                continue
            }
            words.append(char)
        }
        cleaned = words.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
