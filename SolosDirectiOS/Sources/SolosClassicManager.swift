import Foundation
import UIKit
import Combine
import ExternalAccessory
import AVFoundation

struct SolosAccessoryInfo: Identifiable {
    let id: Int
    let name: String
    let manufacturer: String
    let protocols: [String]
}

/// iOS has no public API to open arbitrary Bluetooth Classic RFCOMM sockets.
/// ExternalAccessory works only with manufacturer-approved MFi accessories/protocols.
final class SolosClassicManager: NSObject, ObservableObject, StreamDelegate, AVSpeechSynthesizerDelegate {
    @Published private(set) var accessories: [SolosAccessoryInfo] = []
    @Published private(set) var status = "Checking for compatible Bluetooth accessories..."
    @Published private(set) var connectedName = ""
    @Published private(set) var connectedProtocol = ""
    @Published private(set) var lastFrameSize = 0

    // Exposes only received accessory payloads to user-configured button learning.
    // Unrecognized bytes are never interpreted as controls.
    var onAccessoryPacket: ((Data) -> Void)?
    var onSpeechCompleted: (() -> Void)?
    @Published private(set) var incomingSample = "No accessory messages received"
    private let accessoryManager = EAAccessoryManager.shared()
    private let speaker = AVSpeechSynthesizer()
    private var session: EASession?
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var pendingFrame = Data()
    private var queuedFrames: [Data] = []
    private var nextByte = 0
    @Published private(set) var hudFramesSent = 0

    var declaredProtocols: [String] {
        Bundle.main.object(forInfoDictionaryKey: "UISupportedExternalAccessoryProtocols") as? [String] ?? []
    }

    override init() {
        super.init()
        speaker.delegate = self
        refresh()
    }

    var audioRoute: String {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outputs.map(\.portName).joined(separator: ", ").isEmpty
            ? "No audio route selected"
            : outputs.map(\.portName).joined(separator: ", ")
    }

    func refresh() {
        let found = accessoryManager.connectedAccessories
        accessories = found.map { accessory in
            SolosAccessoryInfo(
                id: accessory.connectionID,
                name: accessory.name,
                manufacturer: accessory.manufacturer,
                protocols: accessory.protocolStrings
            )
        }
        if session == nil {
            status = found.isEmpty
                ? "No MFi Bluetooth accessory exposed to this app. Pair Solos in iPhone Settings, then check again."
                : "Found \(found.count) Apple External Accessory device(s). Check its protocols below."
        }
    }

    func connect(accessoryID: Int, protocolString: String) {
        disconnect()
        guard let accessory = accessoryManager.connectedAccessories.first(where: { $0.connectionID == accessoryID }) else {
            status = "Accessory is no longer connected. Refresh and try again."
            return
        }
        guard accessory.protocolStrings.contains(protocolString) else {
            status = "The accessory does not advertise that protocol."
            return
        }
        guard declaredProtocols.contains(protocolString) else {
            status = "Detected protocol: \(protocolString). Add it to UISupportedExternalAccessoryProtocols in Info.plist and rebuild; Apple requires this before a session can open."
            return
        }
        guard let newSession = EASession(accessory: accessory, forProtocol: protocolString),
              let output = newSession.outputStream,
              let input = newSession.inputStream else {
            status = "iOS refused the accessory session. This protocol might be restricted to the official app."
            return
        }
        session = newSession
        inputStream = input
        outputStream = output
        output.delegate = self
        input.delegate = self
        output.schedule(in: .main, forMode: .common)
        input.schedule(in: .main, forMode: .common)
        input.open()
        output.open()
        connectedName = accessory.name
        connectedProtocol = protocolString
        status = "Opening direct Bluetooth accessory session..."
    }

    func disconnect() {
        inputStream?.close()
        outputStream?.close()
        if let inputStream { inputStream.remove(from: .main, forMode: .common) }
        if let outputStream { outputStream.remove(from: .main, forMode: .common) }
        inputStream?.delegate = nil
        outputStream?.delegate = nil
        inputStream = nil
        outputStream = nil
        session = nil
        connectedName = ""
        connectedProtocol = ""
        pendingFrame = Data()
        queuedFrames.removeAll()
        nextByte = 0
    }

    func openPicker() {
        accessoryManager.showBluetoothAccessoryPicker(withNameFilter: nil) { [weak self] error in
            DispatchQueue.main.async {
                self?.refresh()
                if let error { self?.status = "Pairing picker: \(error.localizedDescription)" }
            }
        }
    }

    func sendHUD(_ text: String) {
        guard session != nil, let outputStream, outputStream.streamStatus == .open else {
            status = "No authorized display connection. HUD preview and Bluetooth audio still work."
            return
        }
        guard let packet = SolosDisplayPacket.imagePacket(message: text) else {
            status = "Failed to encode HUD image."
            return
        }
        enqueuePacket(packet, priority: false)
    }

    func sendHUDImage(_ image: UIImage, priority: Bool = false) {
        guard session != nil, let outputStream, outputStream.streamStatus == .open else {
            status = "NO GLASSES HUD CONNECTION. Connect an exposed Solos ExternalAccessory session."
            return
        }
        guard let packet = SolosDisplayPacket.imagePacket(image: image) else {
            status = "Could not encode OLED image."
            return
        }
        enqueuePacket(packet, priority: priority)
    }

    // A display frame must finish before another one begins. Replacing a partially
    // written Bluetooth packet corrupts the image on actual glasses.
    // Priority frames from Jarvis are queued ahead of dashboard refreshes.
    private func enqueuePacket(_ packet: Data, priority: Bool) {
        let outerFrame = Data([0x1D, 0x60, 0x04, 0x00, 0, 0, 0, 0, 0, 0]) + packet
        if pendingFrame.isEmpty {
            pendingFrame = outerFrame
            nextByte = 0
            lastFrameSize = packet.count
            drain()
        } else if priority {
            queuedFrames.insert(outerFrame, at: 0)
            // Avoid old dashboard images delaying an important answer.
            queuedFrames = Array(queuedFrames.prefix(5))
            status = "Jarvis lens frame queued behind active Bluetooth image."
        } else {
            // Keep the latest dashboard refresh, not a backlog of stale frames.
            if queuedFrames.isEmpty { queuedFrames.append(outerFrame) }
            else { queuedFrames[queuedFrames.count-1] = outerFrame }
        }
    }

    var isSpeaking: Bool { speaker.isSpeaking }

    func interruptSpeech() {
        if speaker.isSpeaking { speaker.stopSpeaking(at:.immediate) }
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.49
        speaker.speak(utterance)
        status = "Speaking using current iPhone audio route: \(audioRoute). Pair Solos as an audio headset first."
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onSpeechCompleted?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onSpeechCompleted?()
    }

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .openCompleted:
            if aStream === outputStream {
                status = "Connected to \(connectedName) via \(connectedProtocol). Send a test image."
                drain()
            }
        case .hasSpaceAvailable:
            drain()
        case .hasBytesAvailable:
            guard let inputStream else { return }
            var temp = [UInt8](repeating: 0, count: 1024)
            while inputStream.hasBytesAvailable {
                let count = inputStream.read(&temp, maxLength: temp.count)
                if count <= 0 { break }
                let received = Data(temp.prefix(count))
                incomingSample = received.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
                onAccessoryPacket?(received)
            }
        case .errorOccurred:
            status = "Bluetooth accessory stream error: \(aStream.streamError?.localizedDescription ?? "unknown")"
            disconnect()
        case .endEncountered:
            status = "Bluetooth accessory session ended."
            disconnect()
        default:
            break
        }
    }

    private func drain() {
        guard let outputStream, outputStream.streamStatus == .open, !pendingFrame.isEmpty else { return }
        while outputStream.hasSpaceAvailable && nextByte < pendingFrame.count {
            let written: Int = pendingFrame.withUnsafeBytes { buffer in
                guard let start = buffer.baseAddress else { return -1 }
                let bytes = start.assumingMemoryBound(to: UInt8.self)
                return outputStream.write(
                    bytes.advanced(by: nextByte),
                    maxLength: min(1024, pendingFrame.count - nextByte)
                )
            }
            if written < 0 {
                status = "Failed sending display packet: \(outputStream.streamError?.localizedDescription ?? "unknown")"
                return
            }
            if written == 0 { break }
            nextByte += written
        }
        if nextByte == pendingFrame.count {
            hudFramesSent += 1
            status = "HUD frame #\(hudFramesSent) transmitted (\(lastFrameSize) bytes). Check the actual lens."
            pendingFrame = Data()
            nextByte = 0
            if !queuedFrames.isEmpty {
                pendingFrame = queuedFrames.removeFirst()
                lastFrameSize = max(0, pendingFrame.count - 10)
                drain()
            }
        }
    }
}
