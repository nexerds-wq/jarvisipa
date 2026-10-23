import Foundation

@main
struct MusicCommandSmoke {
    static func main() {
        let cases: [(String, Bool, JarvisMusicCommand?)] = [
            ("Hey Jarvis play Blinding Lights by The Weeknd", false, .play("Blinding Lights by The Weeknd")),
            ("Hey Jarvis, play the song Bad Romance", false, .play("Bad Romance")),
            ("play Bohemian Rhapsody by Queen", true, .play("Bohemian Rhapsody by Queen")),
            ("Hey Jarvis pause music", false, .pause),
            ("resume music", true, .resume),
            ("Hey Jarvis skip song", false, .next),
            ("previous track", true, .previous),
            ("Hey Jarvis what is Apple Music?", false, nil),
            ("play a song", false, nil),
            ("play", true, .resume),
            ("Hey Jarvis play music", false, .resume),
            ("a song was playing yesterday", true, nil)
        ]
        for (spoken, verified, expected) in cases {
            precondition(JarvisMusicCommand.parse(spoken, wakeAlreadyVerified:verified) == expected,
                         "Wrong result for: \(spoken)")
        }
        print("Jarvis Apple Music voice command checks passed: \(cases.count)")
    }
}
