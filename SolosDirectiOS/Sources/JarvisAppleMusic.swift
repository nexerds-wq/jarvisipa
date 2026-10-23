import Foundation
import Combine
import MusicKit

/// Controls the user's Apple Music app through MusicKit.
@MainActor
final class JarvisAppleMusic: ObservableObject {
    @Published private(set) var status = "Say Hey Jarvis, play [song name]"
    @Published private(set) var nowPlaying = ""
    @Published private(set) var isBusy = false

    private let player = SystemMusicPlayer.shared
    private var requestGeneration = 0

    func playSong(_ spokenQuery:String) {
        let query = spokenQuery.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !query.isEmpty else {
            status = "Tell Jarvis which song you want to play."
            return
        }
        requestGeneration += 1
        let generation = requestGeneration
        status = "Searching Apple Music for \(query)..."
        isBusy = true
        Task { await searchAndPlay(query, generation:generation) }
    }

    private func searchAndPlay(_ query:String, generation:Int) async {
        defer { if requestGeneration == generation { isBusy = false } }
        let authorization = await MusicAuthorization.request()
        guard requestGeneration == generation else { return }
        guard authorization == .authorized else {
            status = "Allow Apple Music access in iPhone Settings to play songs."
            return
        }
        do {
            let subscription = try await MusicSubscription.current
            guard requestGeneration == generation else { return }
            guard subscription.canPlayCatalogContent else {
                status = "Apple Music catalog playback needs an active subscription."
                return
            }
            var request = MusicCatalogSearchRequest(term:query, types:[Song.self])
            request.limit = 10
            let result = try await request.response()
            guard requestGeneration == generation else { return }
            guard let song = result.songs.first else {
                status = "No matching song found for \(query). Try song and artist."
                return
            }
            player.queue = .init(for:[song])
            try await player.play()
            guard requestGeneration == generation else { return }
            nowPlaying = "\(song.title) — \(song.artistName)"
            status = "Now playing: \(nowPlaying)"
        } catch {
            guard requestGeneration == generation else { return }
            status = "Apple Music error: \(error.localizedDescription)"
        }
    }

    func pause() {
        player.pause()
        status = nowPlaying.isEmpty ? "Apple Music paused" : "Paused: \(nowPlaying)"
    }

    func resume() {
        status = "Resuming Apple Music..."
        Task {
            do {
                try await player.play()
                status = nowPlaying.isEmpty ? "Apple Music playing" : "Playing: \(nowPlaying)"
            } catch {
                status = "Unable to resume music: \(error.localizedDescription)"
            }
        }
    }

    func next() {
        status = "Skipping to the next Apple Music song..."
        Task {
            do {
                try await player.skipToNextEntry()
                status = "Playing next Apple Music song"
            } catch {
                status = "Unable to skip song: \(error.localizedDescription)"
            }
        }
    }

    func previous() {
        status = "Going to the previous Apple Music song..."
        Task {
            do {
                try await player.skipToPreviousEntry()
                status = "Playing previous Apple Music song"
            } catch {
                status = "Unable to go back: \(error.localizedDescription)"
            }
        }
    }
}
