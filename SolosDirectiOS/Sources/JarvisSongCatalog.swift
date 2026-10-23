import Foundation

/// Apple's public iTunes Search API returns Store IDs without a MusicKit token.
/// Identifiers can be passed to MPMusicPlayerController.setQueue(with:).
struct JarvisStoreSong: Decodable {
    let trackId: Int64?
    let trackName: String?
    let artistName: String?
    let trackViewUrl: URL?
    let kind: String?

    var identifier: String? { trackId.map(String.init) }
    var label: String { "\(trackName ?? "Song") — \(artistName ?? "Artist")" }
}

struct JarvisStoreSearchResponse: Decodable {
    let resultCount: Int?
    let results: [JarvisStoreSong]
}

enum JarvisSongCatalog {
    enum SearchFailure: LocalizedError {
        case badResponse
        var errorDescription: String? {
            "Couldn't reach the public Apple song search. Check internet access."
        }
    }

    static func search(_ query:String,country:String) async throws -> JarvisStoreSong? {
        var components = URLComponents(string:"https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name:"term",value:query),
            URLQueryItem(name:"country",value:country.lowercased()),
            URLQueryItem(name:"media",value:"music"),
            URLQueryItem(name:"entity",value:"song"),
            URLQueryItem(name:"limit",value:"25")
        ]
        guard let url = components.url else { throw SearchFailure.badResponse }
        var request = URLRequest(url:url)
        request.timeoutInterval = 14
        request.setValue("JarvisSolos/1.0",forHTTPHeaderField:"User-Agent")
        let (data,response) = try await URLSession.shared.data(for:request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SearchFailure.badResponse
        }
        let songs = try JSONDecoder().decode(JarvisStoreSearchResponse.self,from:data).results
        return bestMatch(query:query,songs:songs)
    }

    static func bestMatch(query:String,songs:[JarvisStoreSong]) -> JarvisStoreSong? {
        let (title, artist) = titleAndArtist(query)
        let needle = normalize(title)
        guard !needle.isEmpty else { return nil }
        let artistNeedle = artist.map(normalize)
        let ranked = songs.compactMap { song -> (JarvisStoreSong,Int)? in
            guard song.identifier != nil else { return nil }
            let candidate = normalize(song.trackName ?? "")
            guard !candidate.isEmpty else { return nil }
            let songScore: Int
            if candidate == needle { songScore = 100 }
            else if candidate.hasPrefix(needle + " ") { songScore = 85 }
            else if candidate.contains(needle) { songScore = 65 }
            else if needle.contains(candidate) && candidate.count >= 6 { songScore = 50 }
            else { return nil }

            var artistScore = 0
            if let artistNeedle, !artistNeedle.isEmpty {
                let actualArtist = normalize(song.artistName ?? "")
                if actualArtist == artistNeedle { artistScore = 50 }
                else if actualArtist.contains(artistNeedle) { artistScore = 40 }
                else if artistNeedle.contains(actualArtist) && actualArtist.count >= 4 {
                    artistScore = 25
                } else { return nil }
            }
            if song.kind == "song" { artistScore += 2 }
            return (song,songScore+artistScore)
        }.sorted { $0.1 > $1.1 }
        return ranked.first?.0
    }

    static func titleAndArtist(_ text:String) -> (String,String?) {
        if let range = text.range(of:" by ",options:.caseInsensitive) {
            let song = String(text[..<range.lowerBound])
                .trimmingCharacters(in:.whitespacesAndNewlines)
            let artist = String(text[range.upperBound...])
                .trimmingCharacters(in:.whitespacesAndNewlines)
            if !song.isEmpty && !artist.isEmpty { return (song,artist) }
        }
        return (text.trimmingCharacters(in:.whitespacesAndNewlines),nil)
    }

    static func normalize(_ text:String) -> String {
        let folded = text.folding(options:[.caseInsensitive,.diacriticInsensitive],
                                  locale:Locale(identifier:"en_US")).lowercased()
        return folded.components(separatedBy:CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator:" ")
    }
}
