import Foundation
import AVFoundation
import Combine

/// Optional acoustic-level sensing, separate from speech transcription.
/// This does not diagnose emotion or capture other people's private calls.
@MainActor final class JarvisEmotionCues: ObservableObject {
    @Published private(set) var status = "Acoustic sensing off"
    @Published private(set) var soundLevel: Float = 0
    private let engine = AVAudioEngine()
    private var tapInstalled = false
    private var active = false
    private var lastUpdate = Date.distantPast

    func start() {
        guard !active else { return }
        AVAudioApplication.requestRecordPermission { [weak self] allowed in
            Task { @MainActor in
                guard let self else { return }
                if allowed { self.beginAudio() }
                else { self.status = "Microphone permission denied" }
            }
        }
    }
    private func beginAudio() {
        guard !active else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord,mode:.default,options:[.mixWithOthers,.allowBluetoothHFP])
            try session.setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus:0)
            guard format.channelCount > 0 else {
                status = "No microphone input"
                return
            }
            input.installTap(onBus:0,bufferSize:2048,format:format) { [weak self] buffer,_ in
                guard let data = buffer.floatChannelData?[0] else { return }
                let count = Int(buffer.frameLength)
                guard count > 0 else { return }
                var sum:Float = 0
                for i in 0..<count { sum += data[i] * data[i] }
                let rms = sqrt(sum / Float(count))
                Task { @MainActor [weak self] in
                    guard let self, self.active else { return }
                    guard Date().timeIntervalSince(self.lastUpdate) > 0.6 else { return }
                    self.lastUpdate = Date()
                    self.soundLevel = rms
                    self.status = rms > 0.11 ? "Loud audio detected • emotion unknown" :
                                  rms < 0.005 ? "Quiet audio • emotion unknown" :
                                  "Voice/audio energy detected • emotion unknown"
                }
            }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            active = true
            status = "Acoustic levels active • not emotion recognition"
        } catch {
            if tapInstalled { engine.inputNode.removeTap(onBus:0); tapInstalled = false }
            active = false
            status = "Mic unavailable (another feature may own it): " + error.localizedDescription
        }
    }
    func stop() {
        active = false
        if engine.isRunning { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus:0); tapInstalled = false }
        status = "Acoustic sensing off"
    }
}
