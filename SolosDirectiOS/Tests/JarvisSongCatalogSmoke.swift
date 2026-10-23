import Foundation

@main
struct JarvisSongCatalogSmoke {
    static func main() {
        let songs: [JarvisStoreSong] = [
            .init(trackId:11,trackName:"Blinding Lights",artistName:"The Weeknd",trackViewUrl:nil,kind:"song"),
            .init(trackId:12,trackName:"Blinding Lights (Remix)",artistName:"Another Artist",trackViewUrl:nil,kind:"song"),
            .init(trackId:13,trackName:"Bad Romance",artistName:"Lady Gaga",trackViewUrl:nil,kind:"song"),
            .init(trackId:14,trackName:"Yesterday",artistName:"The Beatles",trackViewUrl:nil,kind:"song")
        ]
        precondition(JarvisSongCatalog.bestMatch(query:"Blinding Lights by The Weeknd",
                                                  songs:songs)?.identifier == "11")
        precondition(JarvisSongCatalog.bestMatch(query:"Bad Romance",
                                                  songs:songs)?.identifier == "13")
        precondition(JarvisSongCatalog.bestMatch(query:"Yesterday by The Beatles",
                                                  songs:songs)?.identifier == "14")
        precondition(JarvisSongCatalog.bestMatch(query:"Totally nonexistent song",
                                                  songs:songs) == nil)
        precondition(JarvisSongCatalog.bestMatch(query:"Blinding Lights by an unknown artist",
                                                  songs:songs) == nil)
        let parsed = JarvisSongCatalog.titleAndArtist("Jolene by Dolly Parton")
        precondition(parsed.0 == "Jolene" && parsed.1 == "Dolly Parton")
        print("Jarvis song catalog matching tests passed (6 cases)")
    }
}
