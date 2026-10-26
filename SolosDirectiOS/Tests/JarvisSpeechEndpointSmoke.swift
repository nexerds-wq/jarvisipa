import Foundation

@main
struct JarvisSpeechEndpointSmoke {
    static func main() {
        let zero = Date(timeIntervalSince1970:0)
        func wait(_ now:Double,_ text:Double,_ voice:Double) -> Double {
            JarvisSpeechEndpoint.remainingWait(
                now:zero.addingTimeInterval(now),
                lastTranscript:zero.addingTimeInterval(text),
                lastVoice:zero.addingTimeInterval(voice))
        }
        precondition(wait(0.5,0,0) > 1.2, "Do not cut off an early thought")
        precondition(wait(2.0,0,1.8) > 0.6, "Live audio extends the listening window")
        precondition(wait(2.9,0,1.8) == 0, "Quiet after a full question submits")
        precondition(wait(6.0,1.0,5.9) == 0, "Background noise cannot block forever")
        precondition(wait(4.1,3.3,0) > 0.9, "New words reset the timer")
        precondition(JarvisSpeechEndpoint.remainingWait(
            now:zero.addingTimeInterval(2.1),lastTranscript:zero,lastVoice:zero,
            patient:true) > 0.5, "Patient mode preserves a thinking pause")
        precondition(JarvisSpeechEndpoint.remainingWait(
            now:zero.addingTimeInterval(3.2),lastTranscript:zero,lastVoice:zero,
            patient:true) == 0, "Patient mode eventually submits a complete thought")
        precondition(JarvisSpeechEndpoint.explicitFinishedQuestion(
            "Hey Jarvis help me make a plan that's all") == "Hey Jarvis help me make a plan",
            "An explicit finishing phrase skips the long delay")
        precondition(JarvisSpeechEndpoint.explicitFinishedQuestion(
            "I'm done with my homework") == nil, "Normal sentences should not be cut")
        print("Jarvis speech endpoint timing passed 9 checks")
    }
}
