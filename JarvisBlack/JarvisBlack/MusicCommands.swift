import Foundation
import MusicKit

enum MusicIntent {
    case play(String)
    case pause
    case resume
    case next
    case stop

    static func parse(_ raw: String) -> MusicIntent? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = cleaned.lowercased()
        if lower == "pause" || lower == "pause music" || lower == "pause the music" {
            return .pause
        }
        if ["resume", "resume music", "continue music", "continue playing"].contains(lower) {
            return .resume
        }
        if ["next", "next song", "skip", "skip song", "skip this song"].contains(lower) {
            return .next
        }
        if ["stop music", "stop the music", "stop playing"].contains(lower) {
            return .stop
        }
        for prefix in ["play the song ", "play some ", "play "] {
            if lower.hasPrefix(prefix) {
                let term = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                return term.isEmpty ? nil : .play(term)
            }
        }
        return nil
    }
}

@MainActor
final class MusicCommands {
    private let player = ApplicationMusicPlayer.shared

    func execute(_ intent: MusicIntent) async -> String {
        do {
            switch intent {
            case .play(let search):
                let permission = await MusicAuthorization.request()
                guard permission == .authorized else {
                    return "Please allow Apple Music access in Settings first."
                }
                var request = MusicCatalogSearchRequest(term: search, types: [Song.self])
                request.limit = 5
                let results = try await request.response()
                guard let song = results.songs.first else {
                    return "I couldn't find \(search) on Apple Music."
                }
                player.queue = ApplicationMusicPlayer.Queue(for: [song])
                try await player.play()
                return "Playing \(song.title) by \(song.artistName)."
            case .pause:
                player.pause()
                return "Paused."
            case .resume:
                try await player.play()
                return "Playing."
            case .next:
                try await player.skipToNextEntry()
                return "Skipping."
            case .stop:
                player.stop()
                return "Music stopped."
            }
        } catch {
            return "I couldn't control Apple Music. Please check your subscription and connection."
        }
    }
}
