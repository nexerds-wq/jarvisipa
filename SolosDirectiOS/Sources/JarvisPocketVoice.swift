import Foundation
import AVFoundation
import FluidAudio

/// Private offline voice playback using streamed 24 kHz PocketTTS frames.
/// A new reply can start playing before the model finishes generating the text.
final class JarvisPocketVoice {
    private let model = PocketTtsManager(language: .english)
    private var voiceData: PocketTtsVoiceData?
    private let audioEngine = AVAudioEngine()
    private let audioPlayer = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 24_000,
                                             channels: 1)!
    private var audioPrepared = false
    private var isPlaying = false
    private var generationTask: Task<Void, Never>?
    private var requestID = 0
    private var scheduledFrames = 0
    private var completedFrames = 0
    private var allFramesGenerated = false
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

    /// Import a personally authorized reference recording through Files.
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
        let current = requestID
        isBusy = true
        finished = onFinish
        failed = onFailure
        generationTask = Task { @MainActor [weak self] in
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

                // Stream 80 ms frames directly to AVAudioEngine. Keep the
                // PocketTTS model and cloned conditioning data loaded between replies.
                let stream = try await model.synthesizeStreaming(text:text,voiceData:voice)
                guard !Task.isCancelled, current == requestID else { return }
                try prepareAudio()
                for try await frame in stream {
                    guard !Task.isCancelled, current == requestID else { return }
                    try schedule(frame.samples, request:current)
                    if !isPlaying {
                        audioPlayer.play()
                        isPlaying = true
                        onStart()
                    }
                }
                guard !Task.isCancelled, current == requestID else { return }
                allFramesGenerated = true
                guard scheduledFrames > 0 else {
                    throw NSError(domain:"JarvisPocketVoice",code:3,userInfo:[
                        NSLocalizedDescriptionKey:"The voice model generated no audio."
                    ])
                }
                completeIfPlayed(request:current)
            } catch {
                guard !Task.isCancelled, current == requestID else { return }
                let callback = failed
                stop()
                callback?(error)
            }
        }
    }

    private func prepareAudio() throws {
        if !audioPrepared {
            audioEngine.attach(audioPlayer)
            audioEngine.attach(timePitch)
            audioEngine.connect(audioPlayer,to:timePitch,format:outputFormat)
            audioEngine.connect(timePitch,to:audioEngine.mainMixerNode,
                                format:outputFormat)
            audioEngine.prepare()
            audioPrepared = true
        }
        let storedSpeed = UserDefaults.standard.object(forKey:"jarvisClonedVoiceSpeed") as? Double
        timePitch.rate = Float(min(1.50,max(0.85,storedSpeed ?? 1.15)))
        if !audioEngine.isRunning {
            try audioEngine.start()
        }
    }

    private func schedule(_ samples:[Float], request:Int) throws {
        guard !samples.isEmpty else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat:outputFormat,
                                            frameCapacity:AVAudioFrameCount(samples.count)),
              let destination = buffer.floatChannelData?[0] else {
            throw NSError(domain:"JarvisPocketVoice",code:4,userInfo:[
                NSLocalizedDescriptionKey:"Unable to create the speech audio buffer."
            ])
        }
        samples.withUnsafeBufferPointer { data in
            if let base = data.baseAddress {
                destination.update(from:base,count:samples.count)
            }
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        scheduledFrames += 1
        audioPlayer.scheduleBuffer(buffer,completionCallbackType:.dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.requestID == request else { return }
                self.completedFrames += 1
                self.completeIfPlayed(request:request)
            }
        }
    }

    private func completeIfPlayed(request:Int) {
        guard request == requestID,allFramesGenerated,
              scheduledFrames > 0, completedFrames >= scheduledFrames else { return }
        let callback = finished
        stop()
        callback?()
    }

    func stop() {
        requestID += 1
        generationTask?.cancel()
        generationTask = nil
        audioPlayer.stop()
        isPlaying = false
        isBusy = false
        scheduledFrames = 0
        completedFrames = 0
        allFramesGenerated = false
        finished = nil
        failed = nil
    }
}
