import Foundation

/// Parses music commands locally rather than sending them to an AI model.
enum JarvisMusicCommand: Equatable {
    case play(String)
    case pause
    case resume
    case next
    case previous

    /// Wake-verified text is the portion returned after "Hey Jarvis".
    static func parse(_ speech:String, wakeAlreadyVerified:Bool = false) -> JarvisMusicCommand? {
        var phrase = speech.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !phrase.isEmpty else { return nil }
        if !wakeAlreadyVerified {
            guard let wake = phrase.range(of:"hey jarvis",
                                         options:[.caseInsensitive,.diacriticInsensitive]) ??
                    phrase.range(of:"oye jarvis",
                                 options:[.caseInsensitive,.diacriticInsensitive]) else {
                return nil
            }
            phrase = String(phrase[wake.upperBound...])
        }
        phrase = phrase.trimmingCharacters(in:
            .whitespacesAndNewlines.union(CharacterSet(charactersIn:",.;:!?")))
        let command = phrase.folding(options:[.caseInsensitive,.diacriticInsensitive],
                                     locale:Locale(identifier:"en_US")).lowercased()

        if ["pause","pause music","stop music","stop song","pause the music"].contains(command) {
            return .pause
        }
        if ["resume","resume music","continue music","continue song",
            "play music","play","unpause"].contains(command) {
            return .resume
        }
        if ["next","next song","next track","skip","skip song",
            "skip track","play next song"].contains(command) {
            return .next
        }
        if ["previous","previous song","previous track","last song",
            "go back a song"].contains(command) {
            return .previous
        }

        let prefixes = ["play the song ","play a song called ","play the track ",
                        "play song ","play ","put on "]
        guard let prefix = prefixes.first(where:{ command.hasPrefix($0) }) else {
            return nil
        }
        let afterPrefix = String(phrase.dropFirst(prefix.count))
            .trimmingCharacters(in:.whitespacesAndNewlines)
        guard !afterPrefix.isEmpty else { return .resume }
        return .play(afterPrefix)
    }
}
