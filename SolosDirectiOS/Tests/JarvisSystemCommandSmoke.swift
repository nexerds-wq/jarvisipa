import Foundation

@main
struct JarvisSystemCommandSmoke {
    static func main() {
        let cases: [(String,Bool,JarvisSystemCommand?)] = [
            ("Hey Jarvis stop",false,.stopCurrent),
            ("Hey Jarvis stop now please",false,.stopCurrent),
            ("Okay Jarvis can you stop for me",false,.stopCurrent),
            ("Hey Jarvis cancel",false,.stopCurrent),
            ("Jarvis that's enough",false,.stopCurrent),
            ("Hey Jarvis stop everything",false,.stopAll),
            ("Hey Jarvis cancel all",false,.stopAll),
            ("Hey Jarvis stop music",false,.stopMusic),
            ("Hey Jarvis stop playing",false,.stopMusic),
            ("Hey Jarvis stop the music please",false,.stopMusic),
            ("Hey Jarvis stop captions",false,.stopCaptions),
            ("Hey Jarvis turn off subtitles",false,.stopCaptions),
            ("Hey Jarvis stop translation",false,.stopTranslation),
            ("Hey Jarvis stop interpreting",false,.stopTranslation),
            ("Hey Jarvis cancel route",false,.stopNavigation),
            ("Hey Jarvis stop navigation",false,.stopNavigation),
            ("Hey Jarvis cancel timer",false,.cancelTimer),
            ("Hey Jarvis stop alarm",false,.cancelTimer),
            ("Hey Jarvis quit",false,.quitJarvis),
            ("Hey Jarvis close app",false,.quitJarvis),
            ("Hey Jarvis end session",false,.quitJarvis),
            ("Hey Jarvis goodbye",false,.quitJarvis),
            ("Hey Jarvis power off",false,.sleepDisplay),
            ("Hey Jarvis power down",false,.sleepDisplay),
            ("Hey Jarvis shut down",false,.sleepDisplay),
            ("Hey Jarvis turn off glasses",false,.sleepDisplay),
            ("Hey Jarvis blank screen",false,.sleepDisplay),
            ("Hey Jarvis sleep",false,.sleepDisplay),
            ("Hey Jarvis go dark",false,.sleepDisplay),
            ("Hey Jarvis stop listening",false,.stopListening),
            ("Hey Jarvis turn off mic",false,.stopListening),
            ("Hey Jarvis start listening",false,.startListening),
            ("Hey Jarvis unmute microphone",false,.startListening),
            ("Hey Jarvis shut up",false,.stopTalking),
            ("Hey Jarvis be quiet",false,.stopTalking),
            ("Hey Jarvis stop talking",false,.stopTalking),
            ("Hey Jarvis wake up",false,.wakeDisplay),
            ("Hey Jarvis power on",false,.wakeDisplay),
            ("Hey Jarvis show hud",false,.wakeDisplay),
            ("Hey Jarvis restart jarvis",false,.wakeDisplay),
            ("stop now",true,.stopCurrent),
            ("power off",true,.sleepDisplay),
            ("wake up",true,.wakeDisplay),
            ("stop everything please",true,.stopAll),
            ("power off my iphone",true,.unsupportedPhonePower),
            ("Hey Jarvis power off my phone",false,.unsupportedPhonePower),
            ("what does power off mean",true,nil),
            ("hey how are you",false,nil),
            ("I want to stop by your house",false,nil),
            ("Hey Jarvis what is the stop sign",false,nil),
            ("Hey Jarvis play a song",false,nil),
            ("Hey Jarvis what happens when my phone dies",false,nil),
        ]
        for (speech,verified,expected) in cases {
            let result = JarvisSystemVoice.parse(speech,wakeAlreadyVerified:verified)
            precondition(result == expected, "\(speech) -> \(String(describing: result)); expected \(String(describing:expected))")
        }
        print("Jarvis system shutdown/wake commands passed \(cases.count) tests")
    }
}
