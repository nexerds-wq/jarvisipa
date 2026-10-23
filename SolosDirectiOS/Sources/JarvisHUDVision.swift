import Foundation
import UIKit
import CoreImage

/// All controls affect the 428x240 frame sent to the Solos HUD, not only the phone preview.
/// Pixel brightness is a software luminance adjustment, NOT the OLED backlight hardware setting.
enum JarvisHUDVision {
    private static let settings = UserDefaults.standard

    static var brightness: CGFloat {
        CGFloat(max(0.35,min(1.7,settings.object(forKey:"hudVisionBrightness") as? Double ?? 1.0)))
    }
    static var contrast: CGFloat {
        CGFloat(max(0.7,min(2.3,settings.object(forKey:"hudVisionContrast") as? Double ?? 1.3)))
    }
    static var sharpening: CGFloat {
        CGFloat(max(0,min(1.4,settings.object(forKey:"hudVisionSharpness") as? Double ?? 0.25)))
    }
    static var textScale: CGFloat {
        CGFloat(max(0.85,min(1.55,settings.object(forKey:"hudVisionTextScale") as? Double ?? 1.12)))
    }
    static var thickText: Bool { settings.object(forKey:"hudVisionBold") as? Bool ?? true }
    static var highVisibility: Bool { settings.bool(forKey:"hudVisionHighVisibility") }

    static var foreground: UIColor { UIColor.white }
    static var accent: UIColor {
        highVisibility ? UIColor.yellow : UIColor(red:0.30,green:1.0,blue:0.78,alpha:1)
    }
    static var dimmed: UIColor {
        highVisibility ? UIColor(white:0.9,alpha:1) : UIColor(red:0.55,green:0.73,blue:0.76,alpha:1)
    }
    static var panel: UIColor {
        highVisibility ? UIColor.black : UIColor(red:0.045,green:0.12,blue:0.135,alpha:1)
    }

    static func apply(to original:UIImage) -> UIImage {
        guard let input = CIImage(image:original) else { return original }
        let extent = CGRect(x:0,y:0,width:428,height:240)
        let color = CIFilter(name:"CIColorControls")
        color?.setValue(input,forKey:kCIInputImageKey)
        color?.setValue(contrast,forKey:kCIInputContrastKey)
        color?.setValue(brightness,forKey:kCIInputBrightnessKey)
        color?.setValue(1.0,forKey:kCIInputSaturationKey)
        var result = color?.outputImage ?? input
        if sharpening > 0 {
            let sharp = CIFilter(name:"CISharpenLuminance")
            sharp?.setValue(result,forKey:kCIInputImageKey)
            sharp?.setValue(sharpening,forKey:kCIInputSharpnessKey)
            result = sharp?.outputImage ?? result
        }
        let ctx = CIContext(options:[.useSoftwareRenderer:false])
        guard let cg = ctx.createCGImage(result.cropped(to:extent),from:extent) else {
            return original
        }
        return UIImage(cgImage:cg,scale:1,orientation:.up)
    }
}
