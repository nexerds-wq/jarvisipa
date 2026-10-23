import SwiftUI
import UIKit

/// A manual, subjective A/B comparison on the REAL 428x240 HUD frame.
/// We never infer inverse optical correction from sphere/cylinder/axis alone.
struct JarvisVisionCalibrationWizard: View {
    @ObservedObject var accessory: SolosClassicManager
    @Environment(\.dismiss) private var dismiss

    @State private var eye: JarvisVisionEye = .right
    @State private var step = 0
    @State private var option = 0
    @State private var working = JarvisVisionProfile.comfortable
    @State private var undoProfiles = [JarvisVisionProfile]()
    @State private var undoOptions = [Int]()
    @State private var sample: UIImage?
    @State private var status = "Compare each image through the glasses."

    private var currentStage: JarvisVisionCalibrationStage {
        JarvisVisionCalibrationStage(rawValue:min(step,2)) ?? .letters
    }

    private var candidate: JarvisVisionProfile {
        step < 3 ? working.variant(stage:currentStage,option:option) : working
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    introduction
                    eyePicker
                    displayPreview
                    if step < 3 {
                        compareControls
                    } else {
                        finishControls
                    }
                    footer
                }
                .padding(16)
            }
            .background(Color.black)
            .navigationTitle("VISION CALIBRATION")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if let active = UserDefaults.standard.string(forKey:"hudVisionActiveEye"),
               let selected = JarvisVisionEye(rawValue:active) { eye = selected }
            showPattern()
        }
    }

    private var introduction: some View {
        VStack(alignment:.leading,spacing:6) {
            Text("FIND WHAT YOUR EYE CAN READ")
                .font(.headline.bold())
                .foregroundStyle(.green)
            Text("Show A, B and C individually. Look through your real Solos lens, then choose the easiest to read without halos. Wear your usual prescription lenses if you use them.")
                .font(.subheadline)
            Text("The display cannot focus light differently for each eye. Profiles are alternatives for the eye actually viewing the HUD, not two simultaneous displays.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var eyePicker: some View {
        VStack(alignment:.leading,spacing:8) {
            Text("WHICH EYE SEES YOUR HUD?")
                .font(.caption.bold())
            HStack {
                ForEach(JarvisVisionEye.allCases) { choice in
                    Button(choice.label) { selectEye(choice) }
                        .buttonStyle(.borderedProminent)
                        .tint(eye == choice ? .green : .gray)
                        .frame(maxWidth:.infinity)
                }
            }
            if JarvisVisionProfileStorage.read(eye) != nil {
                Button("USE MY PREVIOUSLY SAVED \(eye.rawValue) PROFILE") {
                    _ = JarvisVisionProfileStorage.activateSaved(eye)
                    dismiss()
                }
                .font(.caption.bold())
            }
        }
    }

    private var displayPreview: some View {
        VStack(alignment:.leading,spacing:9) {
            HStack {
                Text(step < 3 ? "TEST \(step + 1) OF 3 • \(currentStage.title)" : "FINAL VISION PREVIEW")
                    .font(.subheadline.bold())
                Spacer()
                Text("428 × 240").font(.caption.monospaced())
            }
            if let sample {
                Image(uiImage:sample)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode:.fit)
                    .background(Color.black)
                    .overlay(RoundedRectangle(cornerRadius:8).stroke(.green.opacity(0.55)))
            } else {
                Rectangle()
                    .fill(.black)
                    .aspectRatio(428.0 / 240.0,contentMode:.fit)
            }
            HStack {
                Image(systemName:accessory.connectedProtocol.isEmpty ? "exclamationmark.triangle" : "eyeglasses")
                Text(accessory.connectedProtocol.isEmpty
                     ? "PREVIEW ONLY: no iOS-accessible HUD session. The phone cannot verify lens clarity."
                     : "Display session connected • test frame requested. Check the actual lens.")
            }
            .font(.caption2)
            .foregroundStyle(accessory.connectedProtocol.isEmpty ? .orange : .green)
            Button("SEND THIS IMAGE TO GLASSES AGAIN") { showPattern() }
                .buttonStyle(.bordered)
                .font(.caption)
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.07),in:RoundedRectangle(cornerRadius:12))
    }

    private var compareControls: some View {
        VStack(alignment:.leading,spacing:12) {
            Text(currentStage.instruction)
                .font(.subheadline)
            Text("1. SHOW AN OPTION")
                .font(.caption.bold())
                .foregroundStyle(.green)
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:9) {
                ForEach(0..<currentStage.options.count,id:\.self) { value in
                    Button(currentStage.options[value]) {
                        option = value
                        showPattern()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(option == value ? .green : .gray)
                }
            }
            Text("2. Compare it with the other options. Select your clearest one above.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("USE \(currentStage.options[option]) • NEXT") {
                acceptCandidate()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .frame(maxWidth:.infinity)
            if step > 0 {
                Button("BACK TO PREVIOUS TEST") { goBack() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var finishControls: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("This combination is based on your comparisons. It is not a new eyeglass prescription.")
                .font(.subheadline)
            Text("Text \(Int(working.textScale * 100))% • Contrast \(Int(working.contrast * 100))% • Brightness \(Int(working.brightness * 100))%")
                .font(.caption.monospaced())
            Text("Directional edge enhancement: \(directionLabel(working.directional))")
                .font(.caption)
            Button("SAVE & APPLY TO \(eye.label)") {
                JarvisVisionProfileStorage.saveAndActivate(working,eye:eye)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            Button("BACK TO EDGE TEST") { goBack() }
                .buttonStyle(.bordered)
        }
    }

    private var footer: some View {
        VStack(alignment:.leading,spacing:10) {
            Button("RESTART COMPARISONS") {
                resetComparisons()
            }
            .font(.caption)
            Text("This test adjusts rendered pixels and typography, not the focus of the optical waveguide. Software cannot correct high astigmatism or exceed OLED resolution or brightness. If letters remain doubled or smeared, check proper prescription optics and HUD alignment.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func selectEye(_ value:JarvisVisionEye) {
        eye = value
        resetComparisons()
    }

    private func resetComparisons() {
        working = .comfortable
        undoProfiles.removeAll()
        undoOptions.removeAll()
        step = 0
        option = 0
        showPattern()
    }

    private func acceptCandidate() {
        guard step < 3 else { return }
        undoProfiles.append(working)
        undoOptions.append(option)
        working = candidate
        step += 1
        option = 0
        showPattern()
    }

    private func goBack() {
        guard step > 0 else { return }
        step -= 1
        working = undoProfiles.popLast() ?? .comfortable
        option = undoOptions.popLast() ?? 0
        showPattern()
    }

    private func directionLabel(_ value:Int) -> String {
        switch value {
        case 1: return "Horizontal"
        case 2: return "Vertical"
        case 3: return "Both"
        default: return "Off"
        }
    }

    private func showPattern() {
        let profile = candidate
        let label = step == 3 ? "FINAL • \(eye.rawValue)" : "TEST \(step + 1) • \(["A","B","C","D"][option]) • \(eye.rawValue)"
        let rendered = JarvisVisionCalibrationPattern.make(
            profile:profile,header:label)
        sample = rendered
        if accessory.connectedProtocol.isEmpty {
            status = "Ready on phone only. Connect the HUD display to compare it through the glasses."
        } else {
            accessory.sendHUDImage(rendered,priority:true)
            status = "Requested test frame: \(label). Judge what you see in the lens."
        }
    }
}

/// Unchanged test glyphs between variants: includes confusable characters,
/// small strokes, axes, and a normal-caption example.
enum JarvisVisionCalibrationPattern {
    static func make(profile:JarvisVisionProfile,header:String) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let raw = UIGraphicsImageRenderer(
            size:CGSize(width:428,height:240),format:format).image { context in
            let area = CGRect(x:0,y:0,width:428,height:240)
            UIColor.black.setFill()
            context.cgContext.fill(area)
            let accent: UIColor = profile.highVisibility ? .yellow :
                UIColor(red:0.30,green:1.0,blue:0.78,alpha:1)
            let white = UIColor.white
            let titleFont = UIFont.systemFont(ofSize:15,weight:.bold)
            (header as NSString).draw(at:CGPoint(x:14,y:8),withAttributes:[
                .font:titleFont,.foregroundColor:accent])
            accent.setFill()
            context.cgContext.fill(CGRect(x:14,y:33,width:400,height:2))

            let largeSize = CGFloat(35 * profile.textScale)
            let bigFont = UIFont.systemFont(ofSize:largeSize,weight:.black)
            ("H N X M" as NSString).draw(in:CGRect(x:15,y:48,width:405,height:63),
                                          withAttributes:[.font:bigFont,.foregroundColor:white])
            let sampleFont = UIFont.monospacedSystemFont(
                ofSize:CGFloat(20 * profile.textScale),
                weight:profile.thickText ? .black : .bold)
            ("I l 1   O 0   8 B" as NSString).draw(
                in:CGRect(x:15,y:117,width:403,height:46),
                withAttributes:[.font:sampleFont,.foregroundColor:white])

            // Edge samples: black/white line widths and orientations.
            for i in 0..<10 {
                let x = CGFloat(17 + i * 8)
                white.setFill()
                context.cgContext.fill(CGRect(x:x,y:181,width:i.isMultiple(of:2) ? 1 : 2,height:20))
            }
            for i in 0..<6 {
                let y = CGFloat(181 + i * 4)
                white.setFill()
                context.cgContext.fill(CGRect(x:116,y:y,width:70,height:1))
            }
            let diagonal = UIBezierPath()
            diagonal.move(to:CGPoint(x:202,y:201))
            diagonal.addLine(to:CGPoint(x:225,y:178))
            diagonal.move(to:CGPoint(x:218,y:201))
            diagonal.addLine(to:CGPoint(x:241,y:178))
            diagonal.lineWidth = 1
            white.setStroke()
            diagonal.stroke()
            ("READ CLEARLY" as NSString).draw(
                in:CGRect(x:249,y:181,width:165,height:29),withAttributes:[
                    .font:UIFont.systemFont(ofSize:19,weight:.black),
                    .foregroundColor:accent])
            ("COMPARE • PICK THE CLEAREST, NOT THE BRIGHTEST" as NSString).draw(
                in:CGRect(x:13,y:217,width:402,height:19),withAttributes:[
                    .font:UIFont.systemFont(ofSize:10,weight:.bold),
                    .foregroundColor:white])
        }
        return JarvisHUDVision.apply(to:raw,profile:profile)
    }
}
