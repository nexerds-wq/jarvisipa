import Foundation
import UIKit
import CoreGraphics

/// Solos 2018 HUD: 428 x 240, RGB565 run-length encoded frames.
/// Encoding is based on publicly documented captures of the old Solos Android protocol.
/// Preserves exactly the outer length framing used by our tested Android RFCOMM app.\n/// Bytes still require an authorized iOS Bluetooth Classic accessory session.
enum SolosDisplayPacket {
    static let width = 428
    static let height = 240

    static func render(message: String) -> UIImage {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let cyan = UIColor(red: 0.22, green: 0.92, blue: 0.90, alpha: 1)
            let titleStyle: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 25, weight: .bold),
                .foregroundColor: cyan
            ]
            ("JARVIS  /  SOLOS" as NSString).draw(at: CGPoint(x: 20, y: 14), withAttributes: titleStyle)

            let rule = UIBezierPath()
            rule.move(to: CGPoint(x: 20, y: 51))
            rule.addLine(to: CGPoint(x: 408, y: 51))
            rule.lineWidth = 2
            cyan.setStroke()
            rule.stroke()

            let bodyStyle = NSMutableParagraphStyle()
            bodyStyle.lineBreakMode = .byWordWrapping
            bodyStyle.lineSpacing = 4
            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 23, weight: .medium),
                .foregroundColor: UIColor.white,
                .paragraphStyle: bodyStyle
            ]
            (String(message.prefix(145)) as NSString).draw(
                in: CGRect(x: 20, y: 66, width: 388, height: 130),
                withAttributes: bodyAttributes
            )

            let footerStyle: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .medium),
                .foregroundColor: cyan
            ]
            let clock = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
            (clock as NSString).draw(at: CGPoint(x: 20, y: 207), withAttributes: footerStyle)
        }
    }

    static func imagePacket(message: String) -> Data? {
        imagePacket(image: render(message: message))
    }

    static func imagePacket(image: UIImage) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let hasPixels = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                CGBitmapInfo.byteOrder32Big.rawValue
                  ) else { return false }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard hasPixels else { return nil }

        var rle = Data()
        var previous: UInt16 = 0
        var runCount: UInt8 = 0

        func flush() {
            guard runCount > 0 else { return }
            rle.append(contentsOf: [
                runCount,
                UInt8(truncatingIfNeeded: previous),
                UInt8(truncatingIfNeeded: previous >> 8)
            ])
        }

        // OFF preserves the exact pixel sequence from the V4 build you verified.
        // ON reverses pixel order, which is a 180-degree rotation in row-major RGB565.
        let rotate180 = UserDefaults.standard.bool(forKey: "solosFlip180")
        for i in 0..<(width * height) {
            let offset = rotate180 ? (width * height - i - 1) * 4 : i * 4
            let red = UInt16(rgba[offset] >> 3)
            let green = UInt16(rgba[offset + 1] >> 2)
            let blue = UInt16(rgba[offset + 2] >> 3)
            let rgb565 = (red << 11) | (green << 5) | blue
            if runCount == 0 {
                previous = rgb565
                runCount = 1
            } else if rgb565 == previous && runCount < 255 {
                runCount += 1
            } else {
                flush()
                previous = rgb565
                runCount = 1
            }
        }
        flush()

        // Outer header: 0x601D, type 5 (IMAGE), reserved zero, payload length.
        // Inner header: codec 2 (RLE565), window, chunks, x, y, width, height.
        var frame = Data([0x1D, 0x60, 0x05, 0x00, 0x00, 0x00])
        appendLE(UInt32(rle.count), to: &frame)
        frame.append(contentsOf: [0x02, 0x00])
        appendLE(UInt16(0), to: &frame) // chunk index
        appendLE(UInt16(1), to: &frame) // total chunks
        appendLE(UInt16(0), to: &frame) // x
        appendLE(UInt16(0), to: &frame) // y
        appendLE(UInt16(width), to: &frame)
        appendLE(UInt16(height), to: &frame)
        frame.append(rle)
        return frame
    }

    private static func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { raw in
            data.append(contentsOf: raw)
        }
    }
}
