import Foundation
import UIKit

/// High-contrast, 428x240 native OLED compositions.
/// The frame is still encoded by the same V4 RLE565 image encoder.
enum SolosProHUD {
    static let w: CGFloat = 428
    static let h: CGFloat = 240
    static let mint = UIColor(red: 0.30, green: 1.0, blue: 0.78, alpha: 1)
    static let blue = UIColor(red: 0.35, green: 0.87, blue: 1.0, alpha: 1)
    static let amber = UIColor(red: 1, green: 0.78, blue: 0.36, alpha: 1)
    static let pale = UIColor(white: 0.96, alpha: 1)
    static let dim = UIColor(red: 0.39, green: 0.60, blue: 0.62, alpha: 1)
    static let panel = UIColor(red: 0.045, green: 0.12, blue: 0.135, alpha: 1)

    static func draw(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: UIColor, bold: Bool = false, maxWidth: CGFloat = 400) {
        let weight: UIFont.Weight = bold ? .black : .semibold
        var fontSize = size
        var font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
        var t = text as NSString
        while t.size(withAttributes: [.font: font]).width > maxWidth && fontSize > 12 {
            fontSize -= 1
            font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
        }
        if t.size(withAttributes: [.font: font]).width > maxWidth {
            t = String(text.prefix(max(1, Int(maxWidth / 11)))) as NSString
        }
        t.draw(at: CGPoint(x: x, y: y), withAttributes: [.font:font, .foregroundColor:color])
    }
    static func rect(_ x: CGFloat,_ y: CGFloat,_ width: CGFloat,_ height: CGFloat,_ color: UIColor,_ radius: CGFloat = 0) {
        color.setFill()
        UIBezierPath(roundedRect: CGRect(x:x,y:y,width:width,height:height), cornerRadius:radius).fill()
    }
    static func line(_ x: CGFloat,_ y: CGFloat,_ width: CGFloat,_ color: UIColor, thickness: CGFloat = 1) {
        rect(x,y,width,thickness,color)
    }
    static func header(_ name: String, detail: String) {
        draw("J / S O L O S", x: 13, y: 8, size: 16, color: mint, bold:true, maxWidth:170)
        draw(name, x: 206, y: 9, size: 16, color: pale, bold:true, maxWidth:210)
        line(12,34,404,mint.withAlphaComponent(0.65),thickness:2)
        draw(detail, x: 14, y: 218, size: 13, color: mint, maxWidth:398)
    }
    static func image(mode: Int, clock:String, date:String, steps: Int, distance: String, speed:String, battery:String, gps:String, message:String = "", detail:String = "TAP GLASSES TO CHANGE MODE") -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width:w,height:h),format:format).image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(x:0,y:0,width:w,height:h))
            switch mode {
            case 0:
                header("DASHBOARD",detail:detail)
                draw(clock, x:16,y:46,size:45,color:pale,bold:true,maxWidth:280)
                draw(date.uppercased(),x:20,y:101,size:14,color:mint,maxWidth:260)
                // Glanceable step-goal progress. Defaults to 8,000 steps per local day.
                let progress = min(1.0, max(0.0, Double(steps) / 8000.0))
                rect(20,124,242,4,dim.withAlphaComponent(0.30),2)
                rect(20,124,max(1,242 * progress),4,mint,2)
                let circle = CGPoint(x:359,y:107)
                let ring = UIBezierPath(arcCenter:circle,radius:19,
                    startAngle:-.pi/2,endAngle:CGFloat(3 * Double.pi/2),clockwise:true)
                ring.lineWidth = 4
                dim.withAlphaComponent(0.33).setStroke()
                ring.stroke()
                let filled = UIBezierPath(arcCenter:circle,radius:19,
                    startAngle:-.pi/2,
                    endAngle:-.pi/2 + CGFloat(progress) * .pi * 2,
                    clockwise:true)
                filled.lineWidth = 4
                mint.setStroke()
                filled.stroke()
                draw(String(Int(progress * 100)) + "%", x:343,y:100,size:12,color:pale,bold:true,maxWidth:35)
                rect(12,132,124,70,panel,9)
                rect(149,132,124,70,panel,9)
                rect(286,132,130,70,panel,9)
                draw("STEPS TODAY",x:22,y:138,size:12,color:mint,bold:true,maxWidth:114)
                draw("\(steps)",x:22,y:159,size:30,color:pale,bold:true,maxWidth:112)
                draw("DISTANCE",x:160,y:138,size:12,color:mint,bold:true,maxWidth:110)
                draw(distance,x:160,y:168,size:21,color:pale,bold:true,maxWidth:105)
                draw("SPEED",x:298,y:138,size:12,color:mint,bold:true,maxWidth:110)
                draw(speed,x:298,y:168,size:19,color:pale,bold:true,maxWidth:112)
                draw("PHONE " + battery,x:286,y:50,size:17,color:blue,bold:true,maxWidth:125)
                draw(gps,x:285,y:81,size:12,color:dim,maxWidth:126)
            case 1:
                header("CAPTIONS",detail:detail)
                paragraph(message.isEmpty ? "LISTENING\nFOR SPEECH..." : message, top:49, size:30, maxLines:4)
            case 2:
                header("TRANSLATOR",detail:detail)
                paragraph(message.isEmpty ? "SPEAK TO\nTRANSLATE..." : message, top:49, size:30, maxLines:4)
            case 3:
                header("JARVIS AI",detail:detail)
                paragraph(message.isEmpty ? "HEY JARVIS\nI AM READY." : message, top:49, size:28, maxLines:4)
            default:
                header("SETTINGS",detail:detail)
                paragraph("VISION  •  OLED\nBATTERY " + battery + "\nBUTTON ACTIVE",top:48,size:29,maxLines:4)
            }
        }
    }
    static func paragraph(_ text:String, top:CGFloat,size:CGFloat,maxLines:Int) {
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byWordWrapping
        p.lineSpacing = 4
        let raw = String(text.prefix(210))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize:size,weight:.black),
            .foregroundColor: pale,
            .paragraphStyle:p
        ]
        (raw as NSString).draw(in: CGRect(x:18,y:top,width:392,height:163),withAttributes:attributes)
    }
}
