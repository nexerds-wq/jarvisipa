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
    private var mediaStarted = false
    private var commands = [MPRemoteCommand]()
    var onModeChange: ((Int) -> Void)?
    var onAccessoryShortPress: (() -> Void)?

    private var storedPattern: Data? {
        get {
            guard let string = UserDefaults.standard.string(forKey: "solosLearnedButtonHex"),
                  !string.isEmpty else { return nil }
            var data = Data()
            for piece in string.split(separator: " ") {
                guard let value = UInt8(piece, radix: 16) else { return nil }
                data.append(value)
            }
            return data.isEmpty ? nil : data
        }
        set {
            UserDefaults.standard.set(newValue?.map { String(format: "%02X", $0) }.joined(separator: " ") ?? "", forKey:"solosLearnedButtonHex")
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
        mode = (mode + 1) % 5
        let labels = ["DASHBOARD", "CAPTIONS", "TRANSLATOR", "JARVIS AI", "SETTINGS"]
        status = "Mode \(mode + 1)/5: \(labels[mode])"
        recognizedButtonCount += 1
        onModeChange?(mode)
    }

    func learn() {
        learning = true
        learnUntil = Date().addingTimeInterval(10)
        status = "Now press a glasses button ONCE within 10 seconds. Do not send a HUD image during learning."
        DispatchQueue.main.asyncAfter(deadline:.now()+10) { [weak self] in
            if self?.learning == true {
                self?.learning = false
                self?.status = "No accessory packet detected. Try media controls or NEXT MODE."
            }
        }
    }

    func clearLearnedButton() {
        storedPattern = nil
        learning = false
        status = "Button mapping cleared. The original Bluetooth connection is unchanged."
    }

    func input(_ data: Data) {
        guard !data.isEmpty else { return }
        let fingerprint = data.prefix(12)
        let signature = fingerprint.map { String(format:"%02X", $0) }.joined(separator: " ")
        lastInput = "Accessory: " + signature
        if learning {
            guard Date() <= learnUntil else {
                learning = false
                status = "Learning timed out."
                return
            }
            // Small stable control packets are more plausible button events than image/status
            // payloads. Only store a sample after explicit user learning request.
            guard data.count <= 24 else {
                status = "Received large status packet; press the glasses button again."
                return
            }
            storedPattern = Data(fingerprint)
            learning = false
            status = "Learned  \(signature). Press the same button to cycle HUD modes."
            return
        }
        if let pattern = storedPattern, fingerprint == pattern,
           Date().timeIntervalSince(lastAccessoryInput) > 0.6 {
            lastAccessoryInput = Date()
            nextMode()
        }
    }

    var hasLearnedButton: Bool { storedPattern != nil }
    var learnedDescription: String {
        storedPattern?.map { String(format: "%02X", $0) }.joined(separator:" ") ?? "Not calibrated"
    }

    func stop() {
        commands.forEach { $0.removeTarget(nil) }
        commands.removeAll()
        if mediaStarted { UIApplication.shared.endReceivingRemoteControlEvents() }
        mediaStarted = false
    }
}
