import Foundation
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
final class SolosClassicManager: NSObject, ObservableObject, StreamDelegate {
    @Published private(set) var accessories: [SolosAccessoryInfo] = []
    @Published private(set) var status = "Checking for compatible Bluetooth accessories..."
    @Published private(set) var connectedName = ""
    @Published private(set) var connectedProtocol = ""
    @Published private(set) var lastFrameSize = 0

    private let accessoryManager = EAAccessoryManager.shared()
    private let speaker = AVSpeechSynthesizer()
    private var session: EASession?
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var pendingFrame = Data()
    private var nextByte = 0

    var declaredProtocols: [String] {
        Bundle.main.object(forInfoDictionaryKey: "UISupportedExternalAccessoryProtocols") as? [String] ?? []
    }

    override init() {
        super.init()
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
        nextByte = 0
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
        lastFrameSize = packet.count
        pendingFrame = packet
        nextByte = 0
        drain()
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
                if inputStream.read(&temp, maxLength: temp.count) <= 0 { break }
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
            status = "Sent \(lastFrameSize) bytes to Solos protocol. Check your glasses to confirm it displays."
            pendingFrame = Data()
            nextByte = 0
        }
    }
}
