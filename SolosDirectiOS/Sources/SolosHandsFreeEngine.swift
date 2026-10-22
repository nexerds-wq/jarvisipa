import Foundation
import Combine
import UIKit
import MediaPlayer

/// Controls the HUD through standard iOS media-button events when a headset emits them,
/// or through a user-learned packet from the original Solos accessory session.
/// iOS does not provide an API to directly capture arbitrary headset volume presses.
final class SolosHandsFreeEngine: NSObject, ObservableObject {
    @Published private(set) var mode = 0
    @Published private(set) var status = "Press NEXT MODE on the phone to test. Use LEARN to test glasses controls."
    @Published private(set) var lastInput = "No remote control events received"
    @Published private(set) var learning = false
    @Published private(set) var recognizedButtonCount = 0
    private var lastSwitch = Date.distantPast
    private var learnUntil = Date.distantPast
    private var lastAccessoryInput = Date.distantPast
    private var learnSamples = [Data]()
    private var lastLearnSampleAt = Date.distantPast
    private let requiredLearnSamples = 3
    private var mediaStarted = false
    private var commands = [MPRemoteCommand]()
    var onModeChange: ((Int) -> Void)?
    var onAccessoryShortPress: (() -> Void)?

    private struct LearnedSignature: Codable {
        let bytes: [UInt8]
        let mask: [UInt8]
        let packetLength: Int
    }
    private var learnedSignature: LearnedSignature? {
        get {
            if let data = UserDefaults.standard.data(forKey:"solosLearnedButtonSignatureV20"),
               let signature = try? JSONDecoder().decode(LearnedSignature.self,from:data) {
                return signature
            }
            guard let old = UserDefaults.standard.string(forKey:"solosLearnedButtonHex"),
                  !old.isEmpty else { return nil }
            let bytes = old.split(separator:" ").compactMap { UInt8($0,radix:16) }
            guard !bytes.isEmpty else { return nil }
            return LearnedSignature(bytes:bytes,mask:Array(repeating:255,count:bytes.count),
                                    packetLength:bytes.count)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(try? JSONEncoder().encode(newValue),
                                          forKey:"solosLearnedButtonSignatureV20")
            } else {
                UserDefaults.standard.removeObject(forKey:"solosLearnedButtonSignatureV20")
                UserDefaults.standard.removeObject(forKey:"solosLearnedButtonHex")
            }
        }
    }

    func enableMediaButtons() {
        guard !mediaStarted else { return }
        mediaStarted = true
        UIApplication.shared.beginReceivingRemoteControlEvents()
        let center = MPRemoteCommandCenter.shared()
        let items: [MPRemoteCommand] = [center.playCommand, center.pauseCommand,
                                        center.togglePlayPauseCommand,
                                        center.nextTrackCommand, center.previousTrackCommand]
        for command in items {
            command.addTarget { [weak self] _ in
                DispatchQueue.main.async {
                    self?.lastInput = "iOS forwarded a Bluetooth media button."
                    self?.nextMode()
                }
                return .success
            }
            commands.append(command)
        }
        status = "Media-button listener ready. Solos '+' may act only as volume and not be forwarded by iOS."
    }

    func nextMode() {
        guard Date().timeIntervalSince(lastSwitch) > 0.55 else { return }
        lastSwitch = Date()
        mode = (mode + 1) % 2
        let labels = ["DAILY DASHBOARD", "VOICE NAVIGATION"]
        status = "Mode \(mode + 1)/2: \(labels[mode])"
        recognizedButtonCount += 1
        onModeChange?(mode)
    }

    func learn() {
        learning = true
        learnSamples.removeAll()
        lastLearnSampleAt = .distantPast
        learnUntil = Date().addingTimeInterval(30)
        status = "Press the SAME glasses button 3 separate times within 30 seconds. Pause 1 second between presses."
        DispatchQueue.main.asyncAfter(deadline:.now()+30) { [weak self] in
            guard let self, self.learning, Date() >= self.learnUntil else { return }
            self.learning = false
            self.learnSamples.removeAll()
            self.status = "Learning timed out. Try 3 separate presses; do not send HUD images."
        }
    }

    func clearLearnedButton() {
        learnedSignature = nil
        learning = false
        learnSamples.removeAll()
        status = "Button mapping cleared. The original Bluetooth connection is unchanged."
    }

    func input(_ data: Data) {
        guard !data.isEmpty else { return }
        let fingerprint = Data(data.prefix(12))
        let signature = fingerprint.map { String(format:"%02X",$0) }.joined(separator:" ")
        lastInput = "Accessory (\(data.count) bytes): " + signature
        if learning {
            guard Date() <= learnUntil else {
                learning = false
                learnSamples.removeAll()
                status = "Learning timed out."
                return
            }
            guard data.count >= 2 && data.count <= 24 else {
                status = "Ignored packet of \(data.count) bytes; press the same glasses button."
                return
            }
            guard Date().timeIntervalSince(lastLearnSampleAt) >= 0.85 else { return }
            if let first = learnSamples.first, first.count != data.count {
                status = "Different packet lengths received. Restart LEARN and use one button."
                learnSamples.removeAll()
                lastLearnSampleAt = .distantPast
                return
            }
            lastLearnSampleAt = Date()
            learnSamples.append(data)
            guard learnSamples.count >= requiredLearnSamples else {
                status = "Sample \(learnSamples.count)/\(requiredLearnSamples) recorded. Press SAME button again."
                return
            }
            let length = data.count
            var stable = [UInt8](repeating:255,count:length)
            let baseline = [UInt8](learnSamples[0])
            for sample in learnSamples.dropFirst() {
                let other = [UInt8](sample)
                for i in 0..<length {
                    stable[i] &= ~(baseline[i] ^ other[i])
                }
            }
            let invariantCount = stable.filter { $0 == 255 }.count
            let stableBits = stable.reduce(0) { $0 + $1.nonzeroBitCount }
            guard invariantCount >= 3 && stableBits >= 32 else {
                learning = false
                learnSamples.removeAll()
                status = "Packet changes too much for safe button learning (\(stableBits) stable bits). No mapping saved."
                return
            }
            learnedSignature = LearnedSignature(bytes:baseline,mask:stable,packetLength:length)
            learning = false
            learnSamples.removeAll()
            status = "Learned from 3 presses: \(invariantCount) stable bytes, \(stableBits) stable bits. Test the button."
            return
        }
        if let pattern = learnedSignature,
           data.count == pattern.packetLength,
           pattern.bytes.count == pattern.mask.count,
           pattern.bytes.count <= data.count,
           (0..<pattern.bytes.count).allSatisfy({ index in
               ((pattern.bytes[index] ^ data[index]) & pattern.mask[index]) == 0
           }),
           Date().timeIntervalSince(lastAccessoryInput) > 0.6 {
            lastAccessoryInput = Date()
            nextMode()
        }
    }

    var hasLearnedButton: Bool { learnedSignature != nil }
    var learnedDescription: String {
        guard let signature = learnedSignature else { return "Not calibrated" }
        return zip(signature.bytes,signature.mask).map { byte, mask in
            mask == 255 ? String(format:"%02X",byte) :
            mask == 0 ? "??" : String(format:"%02X/%02X",byte,mask)
        }.joined(separator:" ")
    }

    func stop() {
        commands.forEach { $0.removeTarget(nil) }
        commands.removeAll()
        if mediaStarted { UIApplication.shared.endReceivingRemoteControlEvents() }
        mediaStarted = false
    }
}
