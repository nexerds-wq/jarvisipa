import Foundation

@main
struct JarvisWakePhraseSmoke {
    static func main() {
        let cases: [(String,String?)] = [
            ("Hey Jarvis", ""),
            ("Hey, Jarvis!", ""),
            ("hey jarvis...", ""),
            ("Hey Jarvis what time is it?", "what time is it"),
            ("Hey, Jarvis, tell me a joke", "tell me a joke"),
            ("Please, hey Jarvis, how are you?", "how are you"),
            ("I heard they have jars", nil),
            ("jarvis", nil)
        ]
        for (phrase,expected) in cases {
            let actual = JarvisWakePhrase.question(afterWakeIn:phrase)
            precondition(actual == expected,
                         "\(phrase): got \(String(describing:actual)), expected \(String(describing:expected))")
        }
        print("Jarvis wake phrase parsing passed \(cases.count) tests")
    }
}
