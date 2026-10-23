import Foundation
import Combine
import UIKit
import MediaPlayer

/// Learns stable bytes from separate incoming Solos accessory control packets.
/// This never changes the proven V4 HUD packet encoder or accessory session.
final class SolosHandsFreeEngine: NSObject, ObservableObject {
    enum Button: String, CaseIterable {
        case next = "NEXT"
        case back = "BACK"
        case language = "LANGUAGE"
    }

    static let modeNames = ["DAILY DASHBOARD", "VOICE NAVIGATION",
                            "LIVE CAPTIONS", "TRANSLATE TO ENGLISH", "MESSAGES", "JARVIS", "TIMERS"]
    @Published private(set) var mode = 0
    @Published private(set) var status = "Use NEXT/BACK on the phone or learn glasses button HEX."
    @Published private(set) var lastInput = "No remote control events received"
    @Published private(set) var learning = false
    @Published private(set) var learningAction = ""
    @Published private(set) var recognizedButtonCount = 0
    @Published private(set) var accessoryPacketCount = 0
    @Published private(set) var shortPacketCount = 0
    @Published private(set) var lastMatchedControl = "None yet"
    @Published private(set) var recentShortPackets = [String]()

    private var lastSwitch = Date.distantPast
    private var learnUntil = Date.distantPast
    private var lastAccessoryInput = Date.distantPast
    private var learnSamples = [Data]()
    private var lastLearnSampleAt = Date.distantPast
    private var learningButton: Button?
    private let requiredLearnSamples = 3
    private var mediaStarted = false
    private var commands = [MPRemoteCommand]()

    var onModeChange: ((Int) -> Void)?
    var onLanguageButton: (() -> Void)?

    private struct LearnedSignature: Codable {
        let bytes: [UInt8]
        let mask: [UInt8]
        let packetLength: Int
    }

    private func key(_ button: Button) -> String {
        "solosLearnedHUDButtonV21_" + button.rawValue
    }

    private func storedSignature(for button: Button) -> LearnedSignature? {
        if let encoded = UserDefaults.standard.data(forKey:key(button)),
           let signature = try? JSONDecoder().decode(LearnedSignature.self, from:encoded) {
            return signature
        }
        // Migrate the V20 NEXT mapping; do not silently overwrite it.
        guard button == .next else { return nil }
        if let encoded = UserDefaults.standard.data(forKey:"solosLearnedButtonSignatureV20"),
           let signature = try? JSONDecoder().decode(LearnedSignature.self, from:encoded) {
            return signature
        }
        guard let hex = UserDefaults.standard.string(forKey:"solosLearnedButtonHex") else { return nil }
        let bytes = hex.split(separator:" ").compactMap { UInt8($0,radix:16) }
        guard !bytes.isEmpty else { return nil }
        return LearnedSignature(bytes:bytes, mask:Array(repeating:255,count:bytes.count),
                                packetLength:bytes.count)
    }

    private func store(_ signature: LearnedSignature, for button: Button) {
        UserDefaults.standard.set(try? JSONEncoder().encode(signature), forKey:key(button))
        if button == .next {
            UserDefaults.standard.removeObject(forKey:"solosLearnedButtonSignatureV20")
            UserDefaults.standard.removeObject(forKey:"solosLearnedButtonHex")
        }
    }

    func enableMediaButtons() {
        guard !mediaStarted else { return }
        mediaStarted = true
        UIApplication.shared.beginReceivingRemoteControlEvents()
        let center = MPRemoteCommandCenter.shared()
        for command in [center.playCommand,center.pauseCommand,center.togglePlayPauseCommand,
                        center.nextTrackCommand,center.previousTrackCommand] {
            command.addTarget { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.lastInput = "iOS delivered a headset media control"
                    if command === center.previousTrackCommand {
                        self.previousMode()
                    } else if command === center.playCommand && self.mode == 3 {
                        self.changeLanguage()
                    } else {
                        self.nextMode()
                    }
                }
                return .success
            }
            commands.append(command)
        }
        status = "Media controls active when iOS delivers them. Raw volume presses might not be exposed."
    }

    func setMode(_ value: Int, force: Bool = false) {
        guard (0..<Self.modeNames.count).contains(value) else { return }
        guard force || Date().timeIntervalSince(lastSwitch) >= 0.28 else { return }
        lastSwitch = Date()
        mode = value
        recognizedButtonCount += 1
        status = "HUD \(mode + 1)/\(Self.modeNames.count): \(Self.modeNames[mode])"
        onModeChange?(mode)
    }

    func nextMode(force:Bool = false) {
        setMode((mode + 1) % Self.modeNames.count,force:force)
    }

    func previousMode(force:Bool = false) {
        setMode((mode + Self.modeNames.count - 1) % Self.modeNames.count,force:force)
    }

    func changeLanguage() {
        guard mode == 3 else {
            status = "Go to TRANSLATE HUD to switch the spoken source language."
            return
        }
        status = "Switching translation source language"
        onLanguageButton?()
    }

    func learn() { learn(.next) }
    func learn(_ button: Button) {
        learning = true
        learningButton = button
        learningAction = button.rawValue
        learnSamples.removeAll()
        lastLearnSampleAt = .distantPast
        learnUntil = Date().addingTimeInterval(30)
        status = "LEARN \(button.rawValue): press that SAME glasses button 3 times, one second apart."
        DispatchQueue.main.asyncAfter(deadline:.now()+30) { [weak self] in
            guard let self, self.learning, self.learningButton == button,
                  Date() >= self.learnUntil else { return }
            self.learning = false
            self.learningButton = nil
            self.learnSamples.removeAll()
            self.status = "Learning \(button.rawValue) timed out. Try again without sending HUD images."
        }
    }

    func clearLearnedButton() {
        for button in Button.allCases {
            UserDefaults.standard.removeObject(forKey:key(button))
        }
        UserDefaults.standard.removeObject(forKey:"solosLearnedButtonSignatureV20")
        UserDefaults.standard.removeObject(forKey:"solosLearnedButtonHex")
        learning = false
        learningButton = nil
        learnSamples.removeAll()
        status = "NEXT, BACK and LANGUAGE learned button mappings reset."
    }

    private func matches(_ bytes: Data, _ signature: LearnedSignature) -> Bool {
        // InputStream delivers arbitrary chunks, not guaranteed protocol
        // message boundaries. Match the stable prefix of an incoming chunk
        // rather than rejecting it for extra trailing status/counter bytes.
        guard bytes.count >= signature.bytes.count,
              signature.bytes.count == signature.mask.count,
              signature.bytes.count >= 4 else { return false }
        return (0..<bytes.count).allSatisfy { i in
            ((bytes[i] ^ signature.bytes[i]) & signature.mask[i]) == 0
        }
    }

    func input(_ data: Data) {
        guard !data.isEmpty else { return }
        let fingerprint = Data(data.prefix(12))
        let description = fingerprint.map { String(format:"%02X",$0) }.joined(separator:" ")
        accessoryPacketCount += 1
        if data.count <= 32 {
            shortPacketCount += 1
            recentShortPackets.append(String(format:"%d B: ",data.count) + description)
            if recentShortPackets.count > 8 { recentShortPackets.removeFirst() }
        }
        lastInput = "Accessory (\(data.count) B): " + description

        if learning {
            guard let button = learningButton, Date() <= learnUntil else {
                learning = false
                learningButton = nil
                learnSamples.removeAll()
                status = "Learning timed out."
                return
            }
            guard data.count >= 4 && data.count <= 48 else {
                status = "Ignored \(data.count)-byte packet; learning supports 4–48 byte control frames."
                return
            }
            guard Date().timeIntervalSince(lastLearnSampleAt) > 0.85 else { return }
            lastLearnSampleAt = Date()
            learnSamples.append(Data(data.prefix(12)))
            guard learnSamples.count >= requiredLearnSamples else {
                status = "\(button.rawValue) sample \(learnSamples.count)/3 saved. Press again."
                return
            }
            // Stable HEADERS are useful even when a trailing counter or
            // checksum changes the total frame/chunk length per press.
            let prefixLength = learnSamples.map(\.count).min() ?? 0
            let baseline = [UInt8](learnSamples[0].prefix(prefixLength))
            var stable = [UInt8](repeating:255,count:prefixLength)
            for sample in learnSamples.dropFirst() {
                let other = [UInt8](sample.prefix(prefixLength))
                for i in baseline.indices {
                    stable[i] &= ~(baseline[i] ^ other[i])
                }
            }
            let invariantCount = stable.filter { $0 == 255 }.count
            let stableBits = stable.reduce(0) { $0 + $1.nonzeroBitCount }
            learning = false
            learningButton = nil
            learnSamples.removeAll()
            guard baseline.count >= 4, invariantCount >= 3 && stableBits >= 32 else {
                status = "Not enough stable \(button.rawValue) packet bits. Mapping NOT saved."
                return
            }
            let learned = LearnedSignature(bytes:baseline,mask:stable,packetLength:baseline.count)
            // Refuse ambiguous controls: a learned BACK must be distinct
            // from NEXT and LANGUAGE on all stable bits.
            let collision = Button.allCases.filter({ $0 != button }).contains { other in
                guard let previous = storedSignature(for:other),
                      previous.packetLength == learned.packetLength else { return false }
                return !(0..<learned.bytes.count).contains { i in
                    ((learned.bytes[i] ^ previous.bytes[i]) &
                      learned.mask[i] & previous.mask[i]) != 0
                }
            }
            guard !collision else {
                status = "\(button.rawValue) packet overlaps another control. No mapping saved. Press a DIFFERENT button."
                return
            }
            store(learned,for:button)
            status = "Learned \(button.rawValue) from 3 presses: \(invariantCount) stable bytes / \(stableBits) bits."
            return
        }

        guard Date().timeIntervalSince(lastAccessoryInput) > 0.38 else { return }
        let hits = Button.allCases.filter { button in
            guard let signature = storedSignature(for:button) else { return false }
            return matches(data,signature)
        }
        guard hits.count == 1, let button = hits.first else {
            if hits.count > 1 {
                lastMatchedControl = "AMBIGUOUS"
                status = "Two learned button signatures match; reset and relearn."
            }
            return
        }
        lastMatchedControl = button.rawValue
        lastAccessoryInput = Date()
        switch button {
        case .next: nextMode()
        case .back: previousMode()
        case .language: changeLanguage()
        }
    }

    var hasLearnedButton: Bool {
        Button.allCases.contains { storedSignature(for:$0) != nil }
    }

    func learnedDescription(_ button: Button) -> String {
        guard let signature = storedSignature(for:button) else { return "NOT LEARNED" }
        return zip(signature.bytes,signature.mask).map { byte, mask in
            mask == 255 ? String(format:"%02X",byte) :
            mask == 0 ? "??" : String(format:"%02X/%02X",byte,mask)
        }.joined(separator:" ")
    }

    var learnedDescription: String { learnedDescription(.next) }

    func stop() {
        commands.forEach { $0.removeTarget(nil) }
        commands.removeAll()
        if mediaStarted { UIApplication.shared.endReceivingRemoteControlEvents() }
        mediaStarted = false
    }
}
