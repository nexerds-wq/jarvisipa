import Foundation

@main
struct JarvisSpeechPerformanceSmoke {
    static func main() {
        let samples = JarvisSpeechPerformance.beats(
            for:"I'm sorry you're going through that. We can take this one step at a time. Great news!")
        precondition(samples.count == 3,"Keep natural full-sentence speech units")
        precondition(samples[0].tone == .reassuring,"Support sounds gentle")
        precondition(samples[2].tone == .upbeat,"Good news sounds brighter")
        precondition(JarvisSpeechPerformance.tone(for:"Call 911 right now.") == .urgent,
                     "Emergencies should sound direct")
        precondition(JarvisSpeechPerformance.tone(for:"Plot twist, it worked!") == .playful,
                     "Humor should use a playful delivery")
        let plain = JarvisSpeechPerformance.beats(for:"One sentence. Another sentence.",expressive:false)
        precondition(plain.count == 1 && plain[0].tone == .natural,
                     "Expression can be disabled without losing words")
        let gentle = JarvisSpeechPerformance.adjustments(for:.reassuring,intensity:1)
        let excited = JarvisSpeechPerformance.adjustments(for:.upbeat,intensity:1)
        precondition(gentle.rate < 0 && excited.rate > 0,"Pace reflects delivery")
        print("Jarvis expressive voice passed 7 checks")
    }
}
