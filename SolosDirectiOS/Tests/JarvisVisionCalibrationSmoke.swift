import Foundation

@main
struct JarvisVisionCalibrationSmoke {
    static func main() {
        let starting = JarvisVisionProfile.comfortable
        precondition(starting.isWithinSupportedRanges)
        precondition(JarvisVisionEye.allCases.count == 2)
        precondition(JarvisVisionCalibrationStage.allCases.count == 3)

        for stage in JarvisVisionCalibrationStage.allCases {
            for option in stage.options.indices {
                let variant = starting.variant(stage:stage,option:option)
                precondition(variant.isWithinSupportedRanges,
                    "Invalid calibration preset: \(stage.title), choice \(option)")
            }
        }
        let huge = starting.variant(stage:.letters,option:2)
        precondition(huge.textScale > starting.textScale)
        let yellow = huge.variant(stage:.contrast,option:2)
        precondition(yellow.highVisibility)
        let soft = huge.variant(stage:.contrast,option:0)
        precondition(!soft.highVisibility)
        let left = yellow.variant(stage:.edges,option:2)
        precondition(left.directional == 2)
        let off = yellow.variant(stage:.edges,option:0)
        precondition(off.directional == 0 && off.sharpness == 0)
        precondition(starting.variant(stage:.letters,option:999) == starting)

        let defaults = UserDefaults.standard
        let oldKeys = ["hudVisionProfile_OD","hudVisionProfile_OS","hudVisionActiveEye",
            "hudVisionBrightness","hudVisionContrast","hudVisionSharpness",
            "hudVisionTextScale","hudVisionBold","hudVisionHighVisibility",
            "hudVisionDirectional"]
        let existing: [Any?] = oldKeys.map { defaults.object(forKey:$0) }
        defer {
            for (key,value) in zip(oldKeys,existing) {
                if let value { defaults.set(value,forKey:key) }
                else { defaults.removeObject(forKey:key) }
            }
        }

        JarvisVisionProfileStorage.saveAndActivate(left,eye:.left)
        precondition(JarvisVisionProfileStorage.read(.left) == left)
        precondition(defaults.string(forKey:"hudVisionActiveEye") == "OS")
        JarvisVisionProfileStorage.saveAndActivate(soft,eye:.right)
        precondition(JarvisVisionProfileStorage.read(.right) == soft)
        precondition(defaults.string(forKey:"hudVisionActiveEye") == "OD")
        precondition(JarvisVisionProfileStorage.read(.left) == left,
                     "Activating OD must not overwrite OS profile")
        precondition(JarvisVisionProfileStorage.activateSaved(.left))
        precondition(defaults.integer(forKey:"hudVisionDirectional") == 2)
        precondition(defaults.double(forKey:"hudVisionTextScale") == left.textScale)

        print("Vision calibration presets, persistence and independent eye profiles passed.")
    }
}
