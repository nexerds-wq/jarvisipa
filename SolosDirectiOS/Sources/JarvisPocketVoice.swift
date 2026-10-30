import Foundation
import AVFoundation
import FluidAudio

/// On-device PocketTTS player. Reference samples stay inside the iPhone app.
@MainActor
final class JarvisPocketVoice: NSObject, AVAudioPlayerDelegate {
    private let model = PocketTtsManager(language: .english)
    private var voiceData: PocketTtsVoiceData?
    private var player: AVAudioPlayer?
    private var generationTask: Task<Void, Never>?
    private var requestID = 0
    private var finished: (() -> Void)?
    private var failed: ((Error) -> Void)?
    private(set) var isBusy = false

    static var referenceURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask)[0]
        return folder.appendingPathComponent("jarvis-private-voice.wav")
    }

    static var hasReference: Bool {
        FileManager.default.fileExists(atPath: referenceURL.path)
    }

    /// Import the WAV securely from Files. Never publish voice recordings to GitHub.
    func importWAV(from source: URL) throws {
        guard source.pathExtension.lowercased() == "wav" else {
            throw NSError(domain:"JarvisPocketVoice", code:1, userInfo:[
                NSLocalizedDescriptionKey:"Select ref_audio.wav (WAV format)."
            ])
        }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let audio = try AVAudioFile(forReading: source)
        let seconds = Double(audio.length) / audio.fileFormat.sampleRate
        guard seconds >= 1, seconds <= 30 else {
            throw NSError(domain:"JarvisPocketVoice", code:2, userInfo:[
                NSLocalizedDescriptionKey:"Voice samples must be 1–30 seconds long."
            ])
        }
        let folder = Self.referenceURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let staged = folder.appendingPathComponent("jarvis-voice-import.wav")
        try? FileManager.default.removeItem(at:staged)
        try FileManager.default.copyItem(at:source, to:staged)
        try? FileManager.default.removeItem(at:Self.referenceURL)
        try FileManager.default.moveItem(at:staged, to:Self.referenceURL)
        stop()
        voiceData = nil
    }

    func speak(_ text: String, onStart: @escaping () -> Void,
               onFinish: @escaping () -> Void,
               onFailure: @escaping (Error) -> Void) {
        stop()
        requestID += 1
        let current = requestID
        isBusy = true
        finished = onFinish
        failed = onFailure
        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await model.initialize()
                guard !Task.isCancelled, current == requestID else { return }
                let voice: PocketTtsVoiceData
                if let saved = voiceData {
                    voice = saved
                } else {
                    let cloned = try await model.cloneVoice(from:Self.referenceURL)
                    guard !Task.isCancelled, current == requestID else { return }
                    voiceData = cloned
                    voice = cloned
                }
                let output = try await model.synthesize(text:text, voiceData:voice)
                guard !Task.isCancelled, current == requestID else { return }
                let audioPlayer = try AVAudioPlayer(data:output)
                audioPlayer.delegate = self
                guard audioPlayer.prepareToPlay(), audioPlayer.play() else {
                    throw NSError(domain:"JarvisPocketVoice",code:3,userInfo:[
                        NSLocalizedDescriptionKey:"Could not play the cloned speech."
                    ])
                }
                player = audioPlayer
                onStart()
            } catch {
                guard !Task.isCancelled, current == requestID else { return }
                isBusy = false
                player = nil
                let callback = failed
                finished = nil
                failed = nil
                callback?(error)
            }
        }
    }

    func stop() {
        requestID += 1
        generationTask?.cancel()
        generationTask = nil
        player?.delegate = nil
        player?.stop()
        player = nil
        isBusy = false
        finished = nil
        failed = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard self.player === player else { return }
        self.player = nil
        isBusy = false
        let callback = finished
        finished = nil
        failed = nil
        callback?()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard self.player === player else { return }
        self.player = nil
        isBusy = false
        let callback = failed
        finished = nil
        failed = nil
        callback?(error ?? NSError(domain:"JarvisPocketVoice",code:4,userInfo:[
            NSLocalizedDescriptionKey:"Voice playback failed."
        ]))
    }
}
