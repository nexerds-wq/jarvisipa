import Foundation
import Combine
import MediaPlayer
import StoreKit
import UIKit

/// Voice playback using Apple's public iTunes song search and the system
/// Music player's store-ID queue. The public search requires no MusicKit token.
/// MediaPlayer can request playback for Apple Music catalog songs with a valid
/// subscription; user-library playback remains the offline/permission fallback.
@MainActor
final class JarvisAppleMusic: ObservableObject {
    @Published private(set) var status = "Hey Jarvis, play any Apple Music song"
    @Published private(set) var nowPlaying = ""
    @Published private(set) var isBusy = false
    @Published private(set) var searchURL: URL?

    private let player = MPMusicPlayerController.systemMusicPlayer
    private let cloudService = SKCloudServiceController()
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
        status = "Searching Apple Music for \(query)..."

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
        Task { await searchEntireCatalog(query,requestID:requestID) }
    }

    private func searchEntireCatalog(_ query:String,requestID:Int) async {
        guard generation == requestID else { return }
        do {
            let country = Locale.current.region?.identifier ?? "US"
            guard let song = try await JarvisSongCatalog.search(query,country:country),
                  let storeID = song.identifier else {
                searchLibrary(query,requestID:requestID,
                              context:"That track was not found in the public Apple Music search.")
                return
            }
            guard generation == requestID else { return }
            status = "Found \(song.label) • checking Apple Music playback..."
            let capability: Bool? = await withCheckedContinuation { continuation in
                cloudService.requestCapabilities { capabilities,error in
                    continuation.resume(returning:error == nil ?
                        capabilities.contains(.musicCatalogPlayback) : nil)
                }
            }
            guard generation == requestID else { return }
            if capability == false {
                searchLibrary(query,requestID:requestID,
                    context:"Apple Music catalog playback isn't enabled. Check your subscription.")
                return
            }

            player.stop()
            // This is the Apple-documented MediaPlayer *store identifier*
            // path. It does NOT call MusicCatalogSearchRequest or request a
            // MusicKit developer token.
            player.setQueue(with:[storeID])
            status = "Loading from Apple Music: \(song.label)"
            let preparedError: Error? = await withCheckedContinuation { continuation in
                player.prepareToPlay { error in continuation.resume(returning:error) }
            }
            guard generation == requestID else { return }
            if let preparedError {
                searchLibrary(query,requestID:requestID,
                    context:"Apple Music couldn't prepare this song: \(preparedError.localizedDescription).")
                return
            }
            player.play()
            nowPlaying = song.label
            isBusy = false
            status = "Requested Apple Music playback: \(song.label)"
            // Some iPhone music queues take a moment to begin streaming.
            // Verify playback instead of telling the user it worked without
            // checking the system player's actual state.
            try? await Task.sleep(for:.seconds(3))
            guard generation == requestID else { return }
            if player.playbackState == .playing {
                status = "Now playing: \(song.label)"
                searchURL = nil
            } else {
                status = "Apple Music didn't start this song. Check subscription or tap Open in Apple Music."
            }
        } catch {
            guard generation == requestID else { return }
            searchLibrary(query,requestID:requestID,
                          context:"Public Apple Music search unavailable: \(error.localizedDescription).")
        }
    }

    private func searchLibrary(_ query:String,requestID:Int,context:String) {
        guard generation == requestID else { return }
        status = context + " Checking saved songs..."
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
            status = context + " No saved copy found. Use Open in Apple Music."
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
