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
    static func image(mode: Int, clock:String, date:String, steps: Int, distance: String, speed:String, battery:String, gps:String, message:String = "", detail:String = "TAP GLASSES TO CHANGE MODE", sender:String = "", senderPhoto:UIImage? = nil, messagePage:Int = 1, pageCount:Int = 1) -> UIImage {
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
                header("VOICE NAV",detail:detail)
                let pieces = message.components(separatedBy:"|")
                let distance = pieces.count > 0 ? pieces[0] : "—"
                let direction = pieces.count > 1 ? pieces[1] : "ENTER ADDRESS ON IPHONE"
                let arrival = pieces.count > 2 ? pieces[2] : "—"
                let left = pieces.count > 3 ? pieces[3] : "—"
                draw(distance, x:20,y:43,size:45,color:mint,bold:true,maxWidth:395)
                let p = NSMutableParagraphStyle()
                p.lineBreakMode = .byWordWrapping
                p.lineSpacing = 3
                (String(direction.prefix(88)) as NSString).draw(in:CGRect(x:21,y:99,width:388,height:73),
                    withAttributes:[.font:UIFont.systemFont(ofSize:24,weight:.black),
                                    .foregroundColor:pale,.paragraphStyle:p])
                line(20,180,385,mint.withAlphaComponent(0.45))
                draw("ETA " + arrival,x:21,y:188,size:17,color:blue,bold:true,maxWidth:185)
                draw("LEFT " + left,x:211,y:188,size:17,color:pale,bold:true,maxWidth:195)
            case 2:
                header("LIVE CAPTIONS",detail:detail)
                bigBody(message.isEmpty ? "LISTENING FOR SPEECH..." : String(message.suffix(250)),
                        top:47, height:156, preferred:31, minimum:21)
            case 3:
                header("ENGLISH TRANSLATION",detail:detail)
                bigBody(message.isEmpty ? "LISTENING / TRANSLATING..." : String(message.suffix(250)),
                        top:47, height:156, preferred:31, minimum:21)
            case 4:
                header("MESSAGE",detail:"")
                // Native contact thumbnail is rendered into the actual OLED image.
                rect(12,42,404,63,panel,9)
                if let image = senderPhoto {
                    let target = CGRect(x:19,y:46,width:55,height:55)
                    let context = UIGraphicsGetCurrentContext()
                    context?.saveGState()
                    UIBezierPath(roundedRect:target,cornerRadius:12).addClip()
                    image.draw(in:target)
                    context?.restoreGState()
                } else {
                    rect(19,46,55,55,mint.withAlphaComponent(0.25),12)
                    draw(String(sender.prefix(1)).uppercased(),x:35,y:55,size:32,
                         color:pale,bold:true,maxWidth:36)
                }
                draw(sender.isEmpty ? "MESSAGE" : sender,x:85,y:60,size:22,color:pale,
                     bold:true,maxWidth:324)
                line(16,113,396,mint.withAlphaComponent(0.6))
                bigBody(message.isEmpty ? "NO MESSAGE YET" : message,top:121,height:88,
                        preferred:30,minimum:19)
                draw("MESSAGE \(messagePage)/\(pageCount)  •  PINNED",x:17,y:216,
                     size:12,color:mint,maxWidth:392)
            case 5:
                header("JARVIS ANSWER",detail:detail)
                let p = NSMutableParagraphStyle()
                p.lineBreakMode = .byWordWrapping
                p.lineSpacing = 5
                let answer = message.isEmpty ? "READY TO ANSWER" : message
                (answer as NSString).draw(in:CGRect(x:19,y:46,width:392,height:164),
                    withAttributes:[.font:UIFont.systemFont(ofSize:26,weight:.black),
                                    .foregroundColor:pale,.paragraphStyle:p])
            default:
                header("SETTINGS",detail:detail)
                paragraph("VISION  •  OLED\nBATTERY " + battery + "\nBUTTON ACTIVE",top:48,size:29,maxLines:4)
            }
        }
    }
    static func bigBody(_ text: String, top: CGFloat, height: CGFloat,
                        preferred: CGFloat, minimum: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 3
        let rect = CGRect(x:17,y:top,width:394,height:height)
        var size = preferred
        while size > minimum {
            let font = UIFont.systemFont(ofSize:size,weight:.bold)
            let bounds = (text as NSString).boundingRect(
                with: CGSize(width:rect.width,height:CGFloat.greatestFiniteMagnitude),
                options:[.usesLineFragmentOrigin,.usesFontLeading],
                attributes:[.font:font,.paragraphStyle:paragraph],context:nil)
            if bounds.height <= height { break }
            size -= 1
        }
        (text as NSString).draw(in:rect,withAttributes:[
            .font:UIFont.systemFont(ofSize:size,weight:.bold),
            .foregroundColor:pale,.paragraphStyle:paragraph
        ])
    }

    // A full message is never silently discarded. Text too long for one
    // 428x240 lens is split into pages that remain in MESSAGE HUD mode.
    static func messagePages(_ text: String) -> [String] {
        let clean = text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty else { return ["NO MESSAGE YET"] }
        let font = UIFont.systemFont(ofSize:21,weight:.bold)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 3
        let limit: CGFloat = 88
        let width: CGFloat = 392
        var pages = [String]()
        var current = ""
        for word in clean.split(whereSeparator: { $0.isWhitespace }).map(String.init) {
            let candidate = current.isEmpty ? word : current + " " + word
            let size = (candidate as NSString).boundingRect(
                with:CGSize(width:width,height:CGFloat.greatestFiniteMagnitude),
                options:[.usesLineFragmentOrigin,.usesFontLeading],
                attributes:[.font:font,.paragraphStyle:style],context:nil)
            if size.height > limit && !current.isEmpty {
                pages.append(current)
                current = word
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { pages.append(current) }
        return pages.isEmpty ? ["NO MESSAGE YET"] : pages
    }

    /// Wrap complete AI answers into legible 428x240 OLED pages. Never silently
    /// cut off the last sentence simply because one page is too small.
    static func answerPages(_ answer: String) -> [String] {
        let font = UIFont.systemFont(ofSize:26,weight:.black)
        let words = answer.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return ["READY TO ANSWER"] }
        var pages = [String]()
        var lines = [String]()
        var line = ""
        for word in words {
            let proposed = line.isEmpty ? word : line + " " + word
            if (proposed as NSString).size(withAttributes:[.font:font]).width <= 388 {
                line = proposed
            } else {
                if !line.isEmpty { lines.append(line) }
                if lines.count >= 5 {
                    pages.append(lines.joined(separator:"\n"))
                    lines.removeAll()
                }
                // Extra-long words are shown with UIKit's word wrapping.
                line = word
            }
        }
        if !line.isEmpty { lines.append(line) }
        if !lines.isEmpty { pages.append(lines.joined(separator:"\n")) }
        return Array(pages.prefix(8))
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
