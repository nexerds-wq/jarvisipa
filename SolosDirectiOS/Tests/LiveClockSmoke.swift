import Foundation

@main
struct LiveClockSmoke {
    static func main() {
        let fixed = Date(timeIntervalSince1970: 1_790_000_000)
        let directQuestions = [
            "Hey Jarvis, what time is it?",
            "What is the current time?",
            "What's the time?",
            "How late is it?",
            "Tell me the time",
            "Hey Jarvis, what's today's date?",
            "What date is it today?",
            "What day of the week is it?",
            "What is the date and time?",
            "What year is it?",
            "What month is it?",
            "time",
            "date"
        ]
        for question in directQuestions {
            guard let answer = JarvisLiveClock.answer(for: question, at: fixed),
                  !answer.isEmpty else {
                fatalError("Expected local device-clock answer to: \(question)")
            }
        }
        let questionsForAI = [
            "Who is Robert Downey Jr?",
            "What time did the game start?",
            "What date was the moon landing?",
            "What is the best watch for telling time?",
            "What time is it in London?"
        ]
        for question in questionsForAI {
            precondition(JarvisLiveClock.answer(for: question, at: fixed) == nil,
                         "Must not mistake historical or unrelated question for live clock: \(question)")
        }
        print("JarvisLiveClock passed \(directQuestions.count + questionsForAI.count) live-date/time routing cases")
    }
}
