import Foundation

/// On-device, deterministic voice commands for Jarvis HUD lifecycle.
/// This never calls AI and never claims to switch off the iPhone or glasses.
enum JarvisSystemCommand: Equatable {
    case stopCurrent
    case stopAll
    case stopListening
    case startListening
    case stopTalking
    case stopMusic
    case stopNavigation
    case stopCaptions
    case stopTranslation
    case cancelTimer
    case sleepDisplay
    case wakeDisplay
    case quitJarvis
    case unsupportedPhonePower
}

enum JarvisSystemVoice {
    static func parse(_ utterance:String,wakeAlreadyVerified:Bool = false) -> JarvisSystemCommand? {
        var phrase = utterance.folding(options:[.caseInsensitive,.diacriticInsensitive],
                                       locale:Locale(identifier:"en_US")).lowercased()
        phrase = phrase.components(separatedBy:CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator:" ")

        if !wakeAlreadyVerified {
            // Only act on phrases addressed to Jarvis, not ordinary speech.
            let wakes = ["hey jarvis ", "okay jarvis ", "ok jarvis ",
                         "oye jarvis ", "jarvis ", "hey jarvis", "jarvis"]
            guard let wake = wakes.first(where:{ phrase == $0.trimmingCharacters(in:.whitespaces) ||
                                                        phrase.hasPrefix($0) }) else { return nil }
            phrase = String(phrase.dropFirst(wake.count)).trimmingCharacters(in:.whitespaces)
        }
        while let prefix = ["please ", "can you ", "could you ", "would you ",
                            "will you ", "i want you to "].first(where:phrase.hasPrefix) {
            phrase = String(phrase.dropFirst(prefix.count))
        }
        // Prefix modifiers often occur on both sides of a voice command.
        for _ in 0..<3 {
            if phrase.hasSuffix(" please") { phrase = String(phrase.dropLast(7)) }
            else if phrase.hasSuffix(" right now") { phrase = String(phrase.dropLast(10)) }
            else if phrase.hasSuffix(" now") { phrase = String(phrase.dropLast(4)) }
            else if phrase.hasSuffix(" for me") { phrase = String(phrase.dropLast(7)) }
            else { break }
        }
        phrase = phrase.trimmingCharacters(in:.whitespaces)
        guard !phrase.isEmpty else { return nil }

        let forms: [(JarvisSystemCommand,[String])] = [
            (.unsupportedPhonePower,["power off my phone","turn off my phone",
                "shut down my phone","switch off my phone","power off my iphone",
                "turn off my iphone","shutdown iphone","turn off iphone",
                "shut down iphone","restart my iphone","reboot my phone"]),
            (.stopAll,["stop everything","stop all","stop all tasks","stop all activities",
                "stop everything now","end everything","cancel everything",
                "cancel all","stop all functions","halt everything"]),
            (.stopListening,["stop listening","stop recording","stop the microphone",
                "turn off microphone","turn off the microphone","disable microphone",
                "turn off mic","mic off","microphone off","mute microphone",
                "mute the microphone","mute mic","dont listen","do not listen",
                "stop hearing me","stop listening to me"]),
            (.startListening,["start listening","listen again","resume listening",
                "turn on mic","turn on microphone","turn on the microphone",
                "microphone on","mic on","enable microphone",
                "unmute microphone","unmute mic","start the microphone"]),
            (.stopTalking,["be quiet","quiet","hush","shush","silence",
                "stop talking","stop speaking","stop your voice","stop voice",
                "stop the voice","shut up","dont talk","do not talk",
                "stop reading aloud","silence jarvis"]),
            (.stopMusic,["stop music","stop the music","stop song","stop the song",
                "stop playing music","stop playing","stop playback",
                "pause playback","pause music","pause the music",
                "pause song","pause the song","stop the audio","mute music",
                "turn off music","turn off the music"]),
            (.stopNavigation,["stop navigation","cancel navigation",
                "end navigation","quit navigation","stop navigating",
                "stop directions","cancel directions","stop the directions",
                "stop route","cancel route","cancel the route",
                "end route","end navigation route","stop gps"]),
            (.stopCaptions,["stop captions","stop the captions","end captions",
                "cancel captions","turn off captions","disable captions",
                "stop subtitles","turn off subtitles","stop captioning",
                "stop transcription","stop transcribing"]),
            (.stopTranslation,["stop translation","stop the translation",
                "end translation","cancel translation","stop translator",
                "disable translator","turn off translator","stop translating",
                "turn off translation","stop interpreter","stop interpreting"]),
            (.cancelTimer,["stop timer","stop the timer","cancel timer",
                "cancel the timer","end timer","clear timer","reset timer",
                "turn off timer","stop alarm","cancel alarm","silence alarm"]),
            (.sleepDisplay,["power off","power down","shut down",
                "shutdown","turn off","switch off","sleep",
                "go to sleep","go to standby","standby","stand by",
                "enter standby","blank screen","black screen",
                "turn off screen","turn off the screen","screen off",
                "turn off display","turn off the display","display off",
                "hide hud","hide the hud","disable hud","hide display",
                "go dark","power off jarvis","power down jarvis",
                "shutdown jarvis","shut down jarvis","turn off jarvis",
                "switch off jarvis","turn off glasses","turn off my glasses",
                "power off glasses","power down glasses",
                "shut down glasses","turn off hud","power off hud"]),
            (.wakeDisplay,["wake","wake up","wake up jarvis",
                "wake jarvis","power on","turn on","switch on",
                "boot up","boot jarvis","reboot jarvis","restart jarvis",
                "start jarvis","turn on jarvis","switch on jarvis",
                "show hud","show the hud","show display","display on",
                "screen on","turn on display","turn on the display",
                "turn on screen","resume hud","open hud","open jarvis",
                "come back","im back","wake up glasses",
                "turn on glasses"]),
            (.quitJarvis,["quit","exit","close","quit jarvis",
                "exit jarvis","close jarvis","quit app","exit app",
                "close app","quit the app","exit the app","close the app",
                "terminate","terminate jarvis","end session","end jarvis",
                "end program","goodbye","goodbye jarvis",
                "bye jarvis","sign off","log off","stop jarvis",
                "stop the app","close application","exit application"]),
            (.stopCurrent,["stop","halt","cancel","enough","stop now",
                "please stop","stop it","stop that","cancel that",
                "halt now","stop whatever you are doing",
                "stop what you are doing","stop what youre doing",
                "cut it out","thats enough","that s enough","stop this"])
        ]
        return forms.first(where:{ $0.1.contains(phrase) })?.0
    }
}
