import SwiftUI

// Phone-only presentation. The glasses still receive their original
// high-contrast 428 x 240 frames, not these decorative phone effects.
enum JarvisTheme {
    static let cyan = Color(red:0.30,green:0.84,blue:1.0)
    static let blue = Color(red:0.24,green:0.47,blue:1.0)
    static let orange = Color(red:1.0,green:0.59,blue:0.30)
    static let lavender = Color(red:0.62,green:0.55,blue:1.0)
    static let ink = Color(red:0.022,green:0.039,blue:0.090)
    static let muted = Color(red:0.61,green:0.69,blue:0.81)
    static let panel = Color(red:0.055,green:0.085,blue:0.16)
}

struct JarvisAtmosphere: View {
    var body: some View {
        GeometryReader { _ in
            ZStack {
                LinearGradient(colors:[JarvisTheme.ink,Color(red:0.025,green:0.065,blue:0.135),.black],
                               startPoint:.topLeading,endPoint:.bottomTrailing)
                RadialGradient(colors:[JarvisTheme.blue.opacity(0.30),.clear],
                               center:.topLeading,startRadius:20,endRadius:400)
                RadialGradient(colors:[JarvisTheme.lavender.opacity(0.12),.clear],
                               center:.trailing,startRadius:30,endRadius:330)
                Canvas { context,size in
                    // A transient unbounded GeometryReader measurement must
                    // never create an unbounded drawing loop during launch.
                    guard size.width.isFinite, size.height.isFinite,
                          size.width > 0, size.height > 0 else { return }
                    let width = min(size.width,2048)
                    let height = min(size.height,4096)
                    var grid = Path()
                    for x in stride(from:CGFloat(0),through:width,by:36) {
                        grid.move(to:CGPoint(x:x,y:0))
                        grid.addLine(to:CGPoint(x:x,y:height))
                    }
                    for y in stride(from:CGFloat(0),through:height,by:36) {
                        grid.move(to:CGPoint(x:0,y:y))
                        grid.addLine(to:CGPoint(x:width,y:y))
                    }
                    context.stroke(grid,with:.color(JarvisTheme.cyan.opacity(0.065)),lineWidth:0.5)
                }
                .mask(LinearGradient(colors:[.white.opacity(0.6),.clear],
                                     startPoint:.top,endPoint:.bottom))
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct JarvisCoreOrb: View {
    let userSpeaking: Bool
    let jarvisSpeaking: Bool
    let thinking: Bool
    let level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval:1.0/24.0,
                                paused:reduceMotion || !(userSpeaking || jarvisSpeaking || thinking))) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let animationPhase = time.truncatingRemainder(dividingBy:360)
            let accent = jarvisSpeaking ? JarvisTheme.orange :
                         (userSpeaking ? JarvisTheme.blue : JarvisTheme.cyan)
            let energy = userSpeaking ? min(1.0,0.35 + level * 1.7) :
                         (jarvisSpeaking ? 0.82 : (thinking ? 0.38 : 0.14))
            let beat = reduceMotion ? 0.5 : abs(sin(time * (jarvisSpeaking ? 9 : 13)))
            ZStack {
                Circle()
                    .fill(accent.opacity(0.09 + energy * 0.13))
                    .frame(width:224,height:224)
                    .blur(radius:28)
                Circle()
                    .stroke(accent.opacity(0.18 + energy * 0.28),lineWidth:1.5)
                    .frame(width:230,height:230)
                    .scaleEffect(1 + energy * beat * 0.035)
                Circle()
                    .stroke(AngularGradient(colors:[accent.opacity(0.04),accent,
                                                    .white.opacity(0.8),accent.opacity(0.06)],
                                            center:.center),lineWidth:2)
                    .frame(width:202,height:202)
                    .rotationEffect(.degrees(reduceMotion ? -35 : animationPhase * 17))
                Circle()
                    .trim(from:0.05,to:0.36)
                    .stroke(accent.opacity(0.94),style:StrokeStyle(lineWidth:5,lineCap:.round))
                    .frame(width:184,height:184)
                    .rotationEffect(.degrees(reduceMotion ? 80 : -animationPhase * 30))
                    .shadow(color:accent.opacity(0.8),radius:12)
                Circle()
                    .trim(from:0.5,to:0.78)
                    .stroke(JarvisTheme.lavender.opacity(0.85),
                            style:StrokeStyle(lineWidth:3,lineCap:.round))
                    .frame(width:162,height:162)
                    .rotationEffect(.degrees(reduceMotion ? -30 : animationPhase * 22))
                Circle()
                    .fill(RadialGradient(colors:[accent.opacity(0.40),JarvisTheme.ink.opacity(0.95),
                                                 .black],center:.topLeading,
                                         startRadius:0,endRadius:125))
                    .frame(width:142,height:142)
                    .overlay(Circle().stroke(accent.opacity(0.35),lineWidth:1))
                    .shadow(color:accent.opacity(0.38),radius:25)
                Image(systemName:jarvisSpeaking ? "waveform" :
                      (thinking ? "sparkles" : (userSpeaking ? "mic.fill" : "waveform.path")))
                    .font(.system(size:42,weight:.ultraLight))
                    .foregroundStyle(.white)
                    .shadow(color:accent,radius:18)
                    .scaleEffect(1 + energy * beat * 0.07)
                Circle().fill(accent).frame(width:5,height:5)
                    .offset(y:105)
                    .shadow(color:accent,radius:8)
            }
            .frame(maxWidth:.infinity)
            .frame(height:248)
            .accessibilityLabel(jarvisSpeaking ? "Jarvis speaking" :
                                (userSpeaking ? "Your microphone is hearing you" :
                                 (thinking ? "Jarvis thinking" : "Jarvis standing by")))
        }
    }
}

struct JarvisActionStyle: ButtonStyle {
    let prominent: Bool
    var tint: Color = JarvisTheme.cyan

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size:13,weight:.bold,design:.rounded))
            .frame(maxWidth:.infinity,minHeight:43)
            .foregroundStyle(prominent ? JarvisTheme.ink : .white)
            .background(prominent ? tint : .white.opacity(0.075),
                        in:RoundedRectangle(cornerRadius:13,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:13,style:.continuous)
                .strokeBorder(prominent ? tint.opacity(0.8) : .white.opacity(0.12),lineWidth:1))
            .shadow(color:prominent ? tint.opacity(0.30) : .clear,radius:14,y:5)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.easeOut(duration:0.14),value:configuration.isPressed)
    }
}
