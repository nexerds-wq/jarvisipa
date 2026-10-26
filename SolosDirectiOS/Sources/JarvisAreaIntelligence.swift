import Foundation
import Combine

struct JarvisReportedHeadline: Identifiable {
    let id: String
    let title: String
    let link: URL
    let published: String
}

private final class JarvisNewsFeedParser: NSObject, XMLParserDelegate {
    private(set) var articles: [JarvisReportedHeadline] = []
    private var inItem = false
    private var field = ""
    private var title = ""
    private var link = ""
    private var published = ""

    func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,
                qualifiedName:String?,attributes:[String:String] = [:]) {
        if name == "item" {
            inItem = true
            title = ""; link = ""; published = ""
        }
        field = inItem ? name : ""
    }

    func parser(_ parser:XMLParser,foundCharacters string:String) {
        guard inItem else { return }
        switch field {
        case "title": title += string
        case "link": link += string
        case "pubDate": published += string
        default: break
        }
    }

    func parser(_ parser:XMLParser,didEndElement name:String,namespaceURI:String?,
                qualifiedName:String?) {
        if name == "item" {
            if let url = URL(string:link.trimmingCharacters(in:.whitespacesAndNewlines)),
               ["https","http"].contains(url.scheme?.lowercased() ?? "") {
                let headline = title.trimmingCharacters(in:.whitespacesAndNewlines)
                if !headline.isEmpty {
                    articles.append(JarvisReportedHeadline(id:url.absoluteString,title:headline,
                                                            link:url,published:published))
                }
            }
            inItem = false
        }
        field = ""
    }
}

/// Public news headlines are unverified reports, not live traffic sensors.
@MainActor final class JarvisAreaIntelligence: ObservableObject {
    @Published private(set) var headlines: [JarvisReportedHeadline] = []
    @Published private(set) var researchSummary = ""
    @Published private(set) var sourceURL: URL?
    @Published private(set) var status = "Choose an area to check reported hazards"
    @Published private(set) var loading = false
    @Published private(set) var checkedAt: Date?

    func scanTrafficNews(area:String) async {
        let place = area.trimmingCharacters(in:.whitespacesAndNewlines)
        guard place.count >= 2 else {
            status = "Enter a city or area first. News does not know your exact GPS position."
            return
        }
        await searchNews(query:"\(place) traffic accident road closure danger emergency",area:place)
    }

    func research(_ topic:String) async {
        let query = topic.trimmingCharacters(in:.whitespacesAndNewlines)
        guard query.count >= 2 else { status = "Enter a research topic"; return }
        await searchNews(query:query,area:nil)
        await searchEncyclopedia(query)
    }

    private func searchNews(query:String,area:String?) async {
        loading = true
        defer { loading = false }
        headlines = []
        var components = URLComponents(string:"https://news.google.com/rss/search")
        components?.queryItems = [URLQueryItem(name:"q",value:query),
                                  URLQueryItem(name:"hl",value:"en-US"),
                                  URLQueryItem(name:"gl",value:"US"),
                                  URLQueryItem(name:"ceid",value:"US:en")]
        guard let url = components?.url else { status = "Invalid research query"; return }
        do {
            var request = URLRequest(url:url,timeoutInterval:15)
            request.setValue("JarvisIPA/31 (personal research reader)",forHTTPHeaderField:"User-Agent")
            let (data,response) = try await URLSession.shared.data(for:request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let parser = JarvisNewsFeedParser()
            let xml = XMLParser(data:data)
            xml.delegate = parser
            guard xml.parse() else { throw URLError(.cannotParseResponse) }
            headlines = Array(parser.articles.prefix(7))
            checkedAt = Date()
            if let area {
                status = headlines.isEmpty ? "No matching published headlines returned for \(area)" :
                    "News reports mentioning \(area) • not verified nearby incidents"
            } else {
                status = "Research headlines collected • verify dates and original sources"
            }
        } catch {
            status = "News lookup unavailable: \(error.localizedDescription)"
        }
    }

    private func searchEncyclopedia(_ topic:String) async {
        researchSummary = ""
        sourceURL = nil
        var components = URLComponents(string:"https://en.wikipedia.org/w/api.php")
        components?.queryItems = [URLQueryItem(name:"action",value:"query"),
                                  URLQueryItem(name:"generator",value:"search"),
                                  URLQueryItem(name:"gsrsearch",value:topic),
                                  URLQueryItem(name:"gsrlimit",value:"1"),
                                  URLQueryItem(name:"prop",value:"extracts|info"),
                                  URLQueryItem(name:"exintro",value:"1"),
                                  URLQueryItem(name:"explaintext",value:"1"),
                                  URLQueryItem(name:"inprop",value:"url"),
                                  URLQueryItem(name:"format",value:"json")]
        guard let url = components?.url else { return }
        do {
            let (data,response) = try await URLSession.shared.data(from:url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let json = try JSONSerialization.jsonObject(with:data) as? [String:Any]
            let query = json?["query"] as? [String:Any]
            let pages = query?["pages"] as? [String:[String:Any]] ?? [:]
            if let page = pages.values.first {
                researchSummary = String((page["extract"] as? String ?? "").prefix(1700))
                if let link = page["fullurl"] as? String { sourceURL = URL(string:link) }
            }
        } catch {
            // News results remain useful if this public encyclopedia is down.
        }
    }
}
