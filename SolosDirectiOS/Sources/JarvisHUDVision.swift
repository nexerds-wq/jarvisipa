import Foundation
import UIKit
import CoreImage

/// All controls affect the 428x240 frame sent to the Solos HUD, not only the phone preview.
/// Pixel brightness is a software luminance adjustment, NOT the OLED backlight hardware setting.
enum JarvisHUDVision {
    private static let settings = UserDefaults.standard
    private static let renderingContext = CIContext(options:[.useSoftwareRenderer:false])

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
    static var directionalCorrection: Int {
        max(0,min(3,settings.integer(forKey:"hudVisionDirectional")))
    }
    static var prescriptionAxisStrength: CGFloat {
        CGFloat(max(0,min(1,settings.object(forKey:"hudVisionRxAxisStrength") as? Double ?? 0)))
    }
    static var prescriptionEye: JarvisVisionEye {
        JarvisVisionEye(rawValue:settings.string(forKey:"hudVisionActiveEye") ?? "OD") ?? .right
    }
    /// A bounded, zero-sum, oriented high-pass kernel. This *uses the Rx axis*
    /// but cannot optically undo astigmatism or calculate a diopter correction.
    static func axisKernel(axisDegrees:Int, strength:CGFloat) -> CIVector {
        let radians = Double(axisDegrees) * Double.pi / 180
        let dx = 3.0 * cos(radians)
        let dy = 3.0 * sin(radians)
        var weights = Array(repeating:CGFloat(0),count:49)
        let amount = min(0.22,max(0,Double(strength) * 0.22))
        // Bilinear splat to opposite samples, preserving unit sum and zero DC.
        for sign in [-1.0,1.0] {
            let px = 3 + sign * dx
            let py = 3 + sign * dy
            let x0 = max(0,min(6,Int(floor(px))))
            let y0 = max(0,min(6,Int(floor(py))))
            let fx = px - Double(x0)
            let fy = py - Double(y0)
            for oy in 0...1 {
                for ox in 0...1 {
                    let x = x0 + ox, y = y0 + oy
                    guard x < 7, y < 7 else { continue }
                    let wx = ox == 0 ? (1-fx) : fx
                    let wy = oy == 0 ? (1-fy) : fy
                    let w = CGFloat(amount * wx * wy)
                    weights[y*7+x] -= w
                    weights[24] += w
                }
            }
        }
        weights[24] += 1
        return CIVector(values:weights,count:49)
    }
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

    static func apply(to original:UIImage, profile:JarvisVisionProfile? = nil) -> UIImage {
        let usedBrightness = CGFloat(profile?.brightness ?? Double(brightness))
        let usedContrast = CGFloat(profile?.contrast ?? Double(contrast))
        let usedSharpness = CGFloat(profile?.sharpness ?? Double(sharpening))
        let usedDirectional = profile?.directional ?? directionalCorrection
        guard let input = CIImage(image:original) else { return original }
        let extent = CGRect(x:0,y:0,width:428,height:240)
        let color = CIFilter(name:"CIColorControls")
        color?.setValue(input,forKey:kCIInputImageKey)
        color?.setValue(usedContrast,forKey:kCIInputContrastKey)
        color?.setValue(usedBrightness,forKey:kCIInputBrightnessKey)
        color?.setValue(1.0,forKey:kCIInputSaturationKey)
        var result = color?.outputImage ?? input
        if usedSharpness > 0 {
            let sharp = CIFilter(name:"CISharpenLuminance")
            sharp?.setValue(result,forKey:kCIInputImageKey)
            sharp?.setValue(usedSharpness,forKey:kCIInputSharpnessKey)
            result = sharp?.outputImage ?? result
        }
        if usedDirectional > 0 {
            // Experimental directional unsharp mask. Distinct X/Y kernels
            // may improve perceived stroke separation; NOT a refractive correction.
            let strength: CGFloat = usedDirectional == 3 ? 0.24 : 0.22
            let x: CGFloat = usedDirectional == 2 ? 0 : strength
            let y: CGFloat = usedDirectional == 1 ? 0 : strength
            let kernel = CIVector(values:[
                0,-y,0,
                -x,1+2*x+2*y,-x,
                0,-y,0
            ],count:9)
            let filter = CIFilter(name:"CIConvolution3X3")
            filter?.setValue(result,forKey:kCIInputImageKey)
            filter?.setValue(kernel,forKey:"inputWeights")
            filter?.setValue(0,forKey:"inputBias")
            result = filter?.outputImage ?? result
        }
        let axisStrength = prescriptionAxisStrength
        if axisStrength > 0 {
            let rx = JarvisPrescription.forEye(prescriptionEye)
            let oriented = CIFilter(name:"CIConvolution7X7")
            oriented?.setValue(result,forKey:kCIInputImageKey)
            oriented?.setValue(axisKernel(axisDegrees:rx.axis,strength:axisStrength),
                               forKey:"inputWeights")
            oriented?.setValue(0,forKey:"inputBias")
            result = oriented?.outputImage ?? result
        }
        guard let cg = renderingContext.createCGImage(result.cropped(to:extent),from:extent) else {
            return original
        }
        return UIImage(cgImage:cg,scale:1,orientation:.up)
    }
}
