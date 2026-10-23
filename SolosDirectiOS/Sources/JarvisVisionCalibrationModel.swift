import Foundation

/// The Solos HUD is a single optical image. These are alternative presets
/// for whichever eye actually sees the lens, NOT simultaneous binocular output.
enum JarvisVisionEye: String, CaseIterable, Identifiable {
    case right = "OD"
    case left = "OS"

    var id: String { rawValue }
    var label: String { self == .right ? "RIGHT • OD" : "LEFT • OS" }
}

/// Values transcribed from the user's January 2026 lab receipt; verify against
/// a current signed prescription before ordering physical lenses.
struct JarvisPrescription {
    let sphere: Double
    let cylinder: Double
    let axis: Int
    static func forEye(_ eye:JarvisVisionEye) -> Self {
        eye == .right ? .init(sphere:-2.00,cylinder:-4.50,axis:15) :
                        .init(sphere:-1.75,cylinder:-5.00,axis:160)
    }
    var sphericalEquivalent: Double { sphere + cylinder / 2 }
    var perpendicularMeridian: Int { (axis + 90) % 180 }
    var summary: String {
        String(format:"SPH %.2f D • CYL %.2f D • AXIS %d°",
               sphere,cylinder,axis)
    }
}

enum JarvisVisionCalibrationStage: Int, CaseIterable {
    case letters = 0
    case contrast = 1
    case edges = 2

    var title: String {
        switch self {
        case .letters: return "LETTER SIZE"
        case .contrast: return "COLOR & GLARE"
        case .edges: return "EDGE CLARITY"
        }
    }

    var instruction: String {
        switch self {
        case .letters: return "Compare how easily you read all the letters, not just the biggest ones."
        case .contrast: return "Pick the version with the least glow, halos, and squinting."
        case .edges: return "Pick the cleanest strokes. Sharpening is optional—OFF may look best."
        }
    }

    var options: [String] {
        switch self {
        case .letters: return ["A • REGULAR", "B • LARGE", "C • EXTRA LARGE"]
        case .contrast: return ["A • SOFT WHITE", "B • STRONG WHITE", "C • YELLOW ACCENTS"]
        case .edges: return ["A • NONE", "B • HORIZONTAL", "C • VERTICAL", "D • BOTH"]
        }
    }
}

struct JarvisVisionProfile: Codable, Equatable {
    var brightness: Double
    var contrast: Double
    var sharpness: Double
    var textScale: Double
    var thickText: Bool
    var highVisibility: Bool
    var directional: Int

    /// A conservative accessibility STARTING POINT, not a calculation of
    /// optical correction from diopters. The same defaults for both eyes
    /// intentionally avoid pretending a pixel filter can correct refraction.
    static func prescriptionStartingPoint(_ eye:JarvisVisionEye) -> Self {
        var profile = comfortable
        profile.textScale = 1.42
        profile.contrast = 1.65
        profile.brightness = 1.0
        profile.sharpness = 0.08
        profile.directional = 0
        profile.thickText = true
        return profile
    }

    static let comfortable = JarvisVisionProfile(
        brightness:1.0,contrast:1.35,sharpness:0.12,
        textScale:1.15,thickText:true,highVisibility:false,directional:0)

    func variant(stage:JarvisVisionCalibrationStage, option:Int) -> Self {
        var result = self
        switch stage {
        case .letters:
            let choices = [1.12,1.32,1.52]
            guard choices.indices.contains(option) else { return self }
            result.textScale = choices[option]
            result.thickText = true
        case .contrast:
            guard (0...2).contains(option) else { return self }
            result.highVisibility = option == 2
            result.brightness = [0.92,1.05,0.98][option]
            result.contrast = [1.30,1.72,1.75][option]
            result.sharpness = 0.12
        case .edges:
            guard (0...3).contains(option) else { return self }
            result.directional = option
            result.sharpness = option == 0 ? 0.0 : 0.12
        }
        return result
    }

    var isWithinSupportedRanges: Bool {
        (0.35...1.70).contains(brightness) &&
        (0.7...2.3).contains(contrast) &&
        (0...1.4).contains(sharpness) &&
        (0.85...1.55).contains(textScale) &&
        (0...3).contains(directional)
    }
}

enum JarvisVisionProfileStorage {
    private static let defaults = UserDefaults.standard

    static func read(_ eye:JarvisVisionEye) -> JarvisVisionProfile? {
        guard let saved = defaults.data(forKey:"hudVisionProfile_\(eye.rawValue)"),
              let profile = try? JSONDecoder().decode(JarvisVisionProfile.self,from:saved),
              profile.isWithinSupportedRanges else { return nil }
        return profile
    }

    static func saveAndActivate(_ profile:JarvisVisionProfile, eye:JarvisVisionEye) {
        guard profile.isWithinSupportedRanges else { return }
        if let encoded = try? JSONEncoder().encode(profile) {
            defaults.set(encoded,forKey:"hudVisionProfile_\(eye.rawValue)")
        }
        activate(profile,eye:eye)
    }

    @discardableResult
    static func activateSaved(_ eye:JarvisVisionEye) -> Bool {
        guard let profile = read(eye) else { return false }
        activate(profile,eye:eye)
        return true
    }

    static func activate(_ profile:JarvisVisionProfile, eye:JarvisVisionEye) {
        guard profile.isWithinSupportedRanges else { return }
        defaults.set(eye.rawValue,forKey:"hudVisionActiveEye")
        defaults.set(profile.brightness,forKey:"hudVisionBrightness")
        defaults.set(profile.contrast,forKey:"hudVisionContrast")
        defaults.set(profile.sharpness,forKey:"hudVisionSharpness")
        defaults.set(profile.textScale,forKey:"hudVisionTextScale")
        defaults.set(profile.thickText,forKey:"hudVisionBold")
        defaults.set(profile.highVisibility,forKey:"hudVisionHighVisibility")
        defaults.set(profile.directional,forKey:"hudVisionDirectional")
    }
}
