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

struct JarvisVoiceOption: Identifiable {
    let id: String
    let label: String
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
    // The phone owns wake-word rearming; the HUD has a separate observer so
    // showing the main screen cannot replace the phone's completion callback.
    var onHUDSpeechCompleted: (() -> Void)?
    @Published private(set) var speechIsActive = false
    @Published private(set) var incomingSample = "No accessory messages received"
    private let accessoryManager = EAAccessoryManager.shared()
    private let speaker = AVSpeechSynthesizer()
    private var activeUtterance: AVSpeechUtterance?
    private var session: EASession?
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var pendingFrame = Data()
    // Never queue a backlog of megabytes of obsolete bitmap frames.
    // At most one urgent (message/answer) and one latest ordinary update.
    private var queuedPriorityFrame: Data?
    private var queuedLatestFrame: Data?
    private var nextByte = 0
    private var drainScheduled = false
    private var reconnectWork: DispatchWorkItem?
    private var reconnectAttempt = 0
    private var userDisconnected = false
    private var lastHUDSendAt = Date.distantPast
    private var lastHUDPayloadSize = 0
    private var reconnectObservers = [NSObjectProtocol]()
    private var preferredAccessoryName = UserDefaults.standard.string(forKey:"jarvisPreferredAccessoryName") ?? ""
    private var preferredProtocol = UserDefaults.standard.string(forKey:"jarvisPreferredAccessoryProtocol") ?? ""
    // CPU-heavy RGB565 RLE compression must never stall microphone, SwiftUI
    // or text callbacks on the iPhone main run loop.
    private let imageEncoderQueue = DispatchQueue(label:"solos.fast.hud.encoder",qos:.userInitiated)
    private var latestHUDRequestID = 0
    @Published private(set) var hudFramesSent = 0

    var declaredProtocols: [String] {
        Bundle.main.object(forInfoDictionaryKey: "UISupportedExternalAccessoryProtocols") as? [String] ?? []
    }

    override init() {
        super.init()
        speaker.delegate = self
        refresh()
        let center = NotificationCenter.default
        for name in [Notification.Name.EAAccessoryDidConnect, Notification.Name.EAAccessoryDidDisconnect] {
            reconnectObservers.append(center.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                self?.refresh()
                self?.scheduleReconnect()
            })
        }
        accessoryManager.registerForLocalNotifications()
        scheduleReconnect()
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
            scheduleReconnect()
            if found.isEmpty { status = "Waiting for compatible glasses • auto reconnect enabled" }
        }
    }

    func connect(accessoryID: Int, protocolString: String) {
        userDisconnected = false
        closeStreams()
        reconnectWork?.cancel()
        reconnectWork = nil
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
        preferredAccessoryName = accessory.name
        preferredProtocol = protocolString
        UserDefaults.standard.set(accessory.name,forKey:"jarvisPreferredAccessoryName")
        UserDefaults.standard.set(protocolString,forKey:"jarvisPreferredAccessoryProtocol")
        reconnectAttempt = 0
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
        userDisconnected = true
        reconnectWork?.cancel()
        reconnectWork = nil
        closeStreams()
    }

    private func closeStreams() {
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
        latestHUDRequestID += 1
        pendingFrame = Data()
        queuedPriorityFrame = nil
        queuedLatestFrame = nil
        nextByte = 0
        drainScheduled = false
    }

    private func scheduleReconnect() {
        guard !userDisconnected, session == nil, reconnectWork == nil else { return }
        let delay = min(30.0, Double(1 << min(reconnectAttempt,5)))
        let job = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reconnectWork = nil
            guard !self.userDisconnected, self.session == nil else { return }
            let found = self.accessoryManager.connectedAccessories
            let match = found.first {
                !self.preferredProtocol.isEmpty &&
                $0.protocolStrings.contains(self.preferredProtocol) &&
                (self.preferredAccessoryName.isEmpty || $0.name == self.preferredAccessoryName)
            } ?? found.first {
                $0.protocolStrings.contains(where:self.declaredProtocols.contains)
            }
            if let match, let proto = match.protocolStrings.first(where:self.declaredProtocols.contains) {
                self.connect(accessoryID:match.connectionID,protocolString:proto)
            } else {
                self.reconnectAttempt = min(5,self.reconnectAttempt+1)
                self.scheduleReconnect()
            }
        }
        reconnectWork = job
        DispatchQueue.main.asyncAfter(deadline:.now()+delay,execute:job)
    }

    private func lostConnection(_ reason:String) {
        closeStreams()
        status = reason + " • reconnecting automatically"
        reconnectAttempt = min(5,reconnectAttempt+1)
        scheduleReconnect()
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
        // Limit costly full-frame compression and writes; keep only the newest
        // image rather than overwhelming a slow Classic Bluetooth stream.
        guard Date().timeIntervalSince(lastHUDSendAt) >= (priority ? 0.18 : 0.75) else { return }
        lastHUDSendAt = Date()
        latestHUDRequestID += 1
        let requestID = latestHUDRequestID
        // Serial worker keeps peak memory bounded. Only the latest fully
        // encoded frame gets enqueued; obsolete partial captions are dropped.
        imageEncoderQueue.async { [weak self] in
            let packet = SolosDisplayPacket.imagePacket(image:image)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.latestHUDRequestID == requestID,
                      self.session != nil else { return }
                guard let packet else {
                    self.status = "Could not encode OLED image."
                    return
                }
                guard packet.count <= 180_000 else {
                    self.status = "HUD image too large; skipped to protect Bluetooth"
                    return
                }
                self.enqueuePacket(packet,priority:priority)
            }
        }
    }

    // A display frame must finish before another one begins. Replacing a partially
    // written Bluetooth packet corrupts the image on actual glasses.
    // Priority frames from Jarvis are queued ahead of dashboard refreshes.
    private func enqueuePacket(_ packet: Data, priority: Bool) {
        // Preserves the EXACT manufacturer-protocol framing.
        let outerFrame = Data([0x1D, 0x60, 0x04, 0x00, 0, 0, 0, 0, 0, 0]) + packet
        if pendingFrame.isEmpty {
            pendingFrame = outerFrame
            nextByte = 0
            lastFrameSize = packet.count
            drain()
        } else if priority {
            // Newest critical frame wins. Older unsent HUD pages are stale
            // after a new message, reply or screen has been requested.
            queuedPriorityFrame = outerFrame
            queuedLatestFrame = nil
        } else {
            // Only keep latest normal screen; never displace a critical frame.
            queuedLatestFrame = outerFrame
        }
    }

    var isSpeaking: Bool { speaker.isSpeaking }

    // All choices are voices already available to iOS. There are no accounts,
    // API keys, online TTS requests, or paid services in this voice path.
    var englishVoiceOptions: [JarvisVoiceOption] {
        sortedEnglishVoices().map { voice in
            let quality = voice.quality == .premium ? "Premium" :
                          voice.quality == .enhanced ? "Enhanced" : "Standard"
            return JarvisVoiceOption(id:voice.identifier,
                                     label:"\(voice.name) • \(voice.language) • \(quality)")
        }
    }

    var selectedVoiceLabel: String {
        guard let voice = selectedVoice() else { return "System voice" }
        let quality = voice.quality == .premium ? "Premium" :
                      voice.quality == .enhanced ? "Enhanced" : "Standard"
        return "\(voice.name) • \(quality)"
    }

    private func sortedEnglishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en-") }
            .sorted { lhs,rhs in
                func rank(_ voice:AVSpeechSynthesisVoice) -> Int {
                    let quality = voice.quality == .premium ? 3 :
                                  voice.quality == .enhanced ? 2 : 1
                    return quality * 10 + (voice.language == "en-US" ? 1 : 0)
                }
                if rank(lhs) != rank(rhs) { return rank(lhs) > rank(rhs) }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private func selectedVoice() -> AVSpeechSynthesisVoice? {
        let identifier = UserDefaults.standard.string(forKey:"jarvisVoiceIdentifier") ?? "automatic"
        if identifier != "automatic",
           let selected = AVSpeechSynthesisVoice(identifier:identifier) {
            return selected
        }
        return sortedEnglishVoices().first ?? AVSpeechSynthesisVoice(language:"en-US")
    }

    private func naturalUtterance(_ text:String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string:text)
        utterance.voice = selectedVoice()
        let style = UserDefaults.standard.string(forKey:"jarvisVoiceStyle") ?? "natural"
        let preferredRate = UserDefaults.standard.object(forKey:"jarvisVoiceRate") as? Double ?? 0.50
        let rateChange = style == "bright" ? 0.025 : (style == "calm" ? -0.025 : 0)
        utterance.rate = Float(min(0.62,max(0.40,preferredRate + rateChange)))
        utterance.pitchMultiplier = style == "bright" ? 1.08 : (style == "calm" ? 0.96 : 1.0)
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.03
        utterance.postUtteranceDelay = 0.04
        return utterance
    }

    func interruptSpeech() {
        stopSpeaking()
    }

    /// Voice selection uses installed iOS speech voices; no external TTS API key.
    /// Prefer premium on-device speech when installed, then enhanced, then default.
    /// Uses the currently selected system/Bluetooth audio route.
    func speakCompanion(_ text:String, style:String) {
        let trimmed = text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let utterance = naturalUtterance(trimmed)
        let quality = utterance.voice?.quality == .premium ? "premium" :
                      utterance.voice?.quality == .enhanced ? "enhanced" : "standard"
        beginSpeech(utterance,quality:quality)
    }

    func stopSpeaking() {
        if speaker.isSpeaking { speaker.stopSpeaking(at:.immediate) }
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let utterance = naturalUtterance(trimmed)
        let quality = utterance.voice?.quality == .premium ? "premium" :
                      utterance.voice?.quality == .enhanced ? "enhanced" : "standard"
        beginSpeech(utterance,quality:quality)
    }

    private func beginSpeech(_ utterance: AVSpeechUtterance, quality: String) {
        // Do not switch to an HFP call route for replies: it can make Bluetooth
        // audio silent or low quality. The microphone is paused by the caller.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback,mode:.spokenAudio,
                                    options:[.mixWithOthers,.allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            status = "Jarvis audio setup failed: \(error.localizedDescription)"
            // Try system speech anyway: an existing output route may still work.
        }
        if speaker.isSpeaking { speaker.stopSpeaking(at:.immediate) }
        activeUtterance = utterance
        speechIsActive = false
        speaker.speak(utterance)
        status = "Jarvis voice queued via \(audioRoute) (\(utterance.voice?.name ?? "system voice"), \(quality))"
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        guard utterance === activeUtterance else { return }
        speechIsActive = true
        status = "Jarvis speaking via \(audioRoute)"
    }

    private func finishSpeech(_ utterance: AVSpeechUtterance) {
        // Cancellation of an older utterance must not finish the new answer.
        guard utterance === activeUtterance else { return }
        activeUtterance = nil
        speechIsActive = false
        onSpeechCompleted?()
        onHUDSpeechCompleted?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishSpeech(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finishSpeech(utterance)
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
            lostConnection("Bluetooth stream error")
        case .endEncountered:
            status = "Bluetooth accessory session ended."
            lostConnection("Bluetooth session ended")
        default:
            break
        }
    }

    private func scheduleNextDrain() {
        guard !drainScheduled else { return }
        drainScheduled = true
        DispatchQueue.main.asyncAfter(deadline:.now()+0.008) { [weak self] in
            guard let self else { return }
            self.drainScheduled = false
            self.drain()
        }
    }

    private func drain() {
        guard let outputStream, outputStream.streamStatus == .open,
              !pendingFrame.isEmpty else { return }
        // Yield to iOS between chunks of a large (potentially >100KB)
        // OLED frame instead of blocking the UI thread for the whole write.
        var writtenThisPass = 0
        let budget = 16 * 1024
        while outputStream.hasSpaceAvailable && nextByte < pendingFrame.count &&
              writtenThisPass < budget {
            let written: Int = pendingFrame.withUnsafeBytes { buffer in
                guard let start = buffer.baseAddress else { return -1 }
                let bytes = start.assumingMemoryBound(to:UInt8.self)
                return outputStream.write(bytes.advanced(by:nextByte),
                                          maxLength:min(1024,pendingFrame.count-nextByte))
            }
            if written < 0 {
                status = "Failed sending display packet: \(outputStream.streamError?.localizedDescription ?? "unknown")"
                lostConnection("HUD write failed")
                return
            }
            if written == 0 { break }
            nextByte += written
            writtenThisPass += written
        }

        if nextByte == pendingFrame.count {
            hudFramesSent += 1
            status = "HUD frame #\(hudFramesSent) transmitted (\(lastFrameSize) bytes). Check the actual lens."
            pendingFrame = Data()
            nextByte = 0
            if let priority = queuedPriorityFrame {
                pendingFrame = priority
                queuedPriorityFrame = nil
            } else if let latest = queuedLatestFrame {
                pendingFrame = latest
                queuedLatestFrame = nil
            }
            if !pendingFrame.isEmpty {
                lastFrameSize = max(0,pendingFrame.count-10)
            }
        }
        if !pendingFrame.isEmpty && outputStream.hasSpaceAvailable {
            scheduleNextDrain()
        }
    }

}
