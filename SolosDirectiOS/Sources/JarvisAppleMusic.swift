import Foundation
import Combine
import MediaPlayer
import UIKit

/// Apple Music playback that also works with free sideloaded builds:
/// MediaPlayer can play items in the user's Music library without ever
/// requesting the MusicKit developer token. Full Apple Music catalog search
/// still requires MusicKit App Service, so unknown songs get a Music app link.
@MainActor
final class JarvisAppleMusic: ObservableObject {
    @Published private(set) var status = "Hey Jarvis, play a song from my Music library"
    @Published private(set) var nowPlaying = ""
    @Published private(set) var isBusy = false
    @Published private(set) var searchURL: URL?

    private let player = MPMusicPlayerController.systemMusicPlayer
    private var generation = 0

    func playSong(_ spokenQuery: String) {
        let query = spokenQuery.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !query.isEmpty else {
            status = "Say the song title and artist."
            return
        }
        generation += 1
        let id = generation
        searchURL = appleMusicSearchURL(for:query)
        isBusy = true
        status = "Searching your Apple Music library for \(query)..."

        switch MPMediaLibrary.authorizationStatus() {
        case .notDetermined:
            MPMediaLibrary.requestAuthorization { [weak self] permission in
                Task { @MainActor [weak self] in
                    self?.continueSearch(query,requestID:id,permission:permission)
                }
            }
        case .authorized:
            continueSearch(query,requestID:id,permission:.authorized)
        case .denied, .restricted:
            continueSearch(query,requestID:id,
                           permission:MPMediaLibrary.authorizationStatus())
        @unknown default:
            isBusy = false
            status = "Music library access unavailable. Use Open in Apple Music."
        }
    }

    private func continueSearch(_ query:String,requestID:Int,
                                permission:MPMediaLibraryAuthorizationStatus) {
        guard generation == requestID else { return }
        guard permission == .authorized else {
            isBusy = false
            status = "Allow Media & Apple Music access in iPhone Settings, or open this song in Apple Music."
            return
        }
        let (title,artist) = Self.songAndArtist(from:query)
        let titleKey = Self.normalized(title)
        let artistKey = artist.map(Self.normalized)

        // This is a local *library* query, not MusicCatalogSearchRequest.
        // No developer token or Apple Developer Program App Service needed.
        let collection = MPMediaQuery.songs()
        let items = collection.items ?? []
        let matches = items.filter { item in
            let songKey = Self.normalized(item.title ?? "")
            guard !songKey.isEmpty, songKey.contains(titleKey) ||
                  titleKey.contains(songKey) else { return false }
            if let artistKey, !artistKey.isEmpty {
                return Self.normalized(item.artist ?? "").contains(artistKey)
            }
            return true
        }
        let chosen = matches.first(where: { Self.normalized($0.title ?? "") == titleKey })
            ?? matches.first

        guard let song = chosen else {
            isBusy = false
            status = "Not in your Music library: \(query). Tap Open in Apple Music to search the full catalog."
            return
        }

        // Keep the library queue so Next and Previous have entries to skip.
        player.stop()
        player.setQueue(with:collection)
        player.nowPlayingItem = song
        let displayName = "\(song.title ?? title) — \(song.artist ?? "Unknown artist")"
        status = "Loading \(displayName)..."
        player.prepareToPlay { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == requestID else { return }
                self.isBusy = false
                if let error {
                    self.status = "Couldn't play the library song: \(error.localizedDescription). Try Open in Apple Music."
                    return
                }
                self.player.play()
                self.nowPlaying = displayName
                self.searchURL = nil
                self.status = "Playing from your library: \(displayName)"
            }
        }
    }

    func openSearchInMusic() {
        guard let searchURL else {
            status = "Say a song name first, then open Apple Music search."
            return
        }
        UIApplication.shared.open(searchURL, options:[:]) { [weak self] opened in
            Task { @MainActor [weak self] in
                self?.status = opened
                    ? "Search opened in Apple Music. Select the track to play."
                    : "Couldn't open Apple Music. Try searching directly in the Music app."
            }
        }
    }

    func pause() {
        player.pause()
        status = nowPlaying.isEmpty ? "Music paused" : "Paused: \(nowPlaying)"
    }

    func resume() {
        player.play()
        status = nowPlaying.isEmpty ? "Resumed current Apple Music playback" :
            "Playing: \(nowPlaying)"
    }

    func next() {
        player.skipToNextItem()
        refreshNowPlaying(label:"Next song")
    }

    func previous() {
        player.skipToPreviousItem()
        refreshNowPlaying(label:"Previous song")
    }

    private func refreshNowPlaying(label:String) {
        if let current = player.nowPlayingItem {
            nowPlaying = "\(current.title ?? "Song") — \(current.artist ?? "Artist")"
            status = "\(label): \(nowPlaying)"
        } else {
            status = "\(label) requested in the Music app"
        }
    }

    private func appleMusicSearchURL(for query:String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "music.apple.com"
        components.path = "/\(Locale.current.region?.identifier.lowercased() ?? "us")/search"
        components.queryItems = [URLQueryItem(name:"term",value:query)]
        return components.url
    }

    private static func songAndArtist(from spoken:String) -> (String,String?) {
        if let split = spoken.range(of:" by ",options:.caseInsensitive) {
            let title = String(spoken[..<split.lowerBound]).trimmingCharacters(in:.whitespaces)
            let artist = String(spoken[split.upperBound...]).trimmingCharacters(in:.whitespaces)
            if !title.isEmpty && !artist.isEmpty { return (title,artist) }
        }
        return (spoken,nil)
    }

    private static func normalized(_ text:String) -> String {
        let folded = text.folding(options:[.caseInsensitive,.diacriticInsensitive],
                                  locale:Locale(identifier:"en_US")).lowercased()
        return folded.components(separatedBy:CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator:" ")
    }
}
