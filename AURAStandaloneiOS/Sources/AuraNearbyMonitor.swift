import CoreLocation
import Foundation
import UIKit

// Network lookups are opt-in and run only while AURA is active. No API key,
// background-location entitlement, or tracking history is required.
@MainActor
final class AuraNearbyMonitor: NSObject, CLLocationManagerDelegate {
    var onChime: ((String) -> Void)?
    var onStatus: ((String) -> Void)?

    private let locationManager = CLLocationManager()
    private var location: CLLocation?
    private var locality: String?
    private var state: String?
    private var checkTask: Task<Void, Never>?
    private var lookupInProgress = false
    private var weatherEnabled = false
    private var newsEnabled = false
    private var seenNews: Set<String> = []
    private var newsSeeded = false
    private var lastRainChime = Date.distantPast

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    func configure(weather: Bool, news: Bool) {
        weatherEnabled = weather
        newsEnabled = news
        checkTask?.cancel()
        checkTask = nil
        guard weather || news else {
            onStatus?("Nearby alerts are off.")
            return
        }
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
            startChecking()
        case .notDetermined:
            onStatus?("Allow location while using AURA to check nearby alerts.")
            locationManager.requestWhenInUseAuthorization()
        default:
            onStatus?("Location access is off. Enable it in iPhone Settings to use nearby alerts.")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard weatherEnabled || newsEnabled else { return }
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        location = latest
        // Resolve a locality, not a street address; only the city is used for news.
        if newsEnabled && locality == nil {
            CLGeocoder().reverseGeocodeLocation(latest) { [weak self] places, _ in
                Task { @MainActor [weak self] in
                    guard let self, let place = places?.first else { return }
                    self.locality = place.locality ?? place.subAdministrativeArea
                    self.state = place.administrativeArea
                }
            }
        }
        startChecking()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onStatus?("Location temporarily unavailable: \(error.localizedDescription)")
    }

    @objc private func appBecameActive() {
        guard weatherEnabled || newsEnabled else { return }
        if location == nil { locationManager.requestLocation() }
        startChecking()
    }

    private func startChecking() {
        guard location != nil, (weatherEnabled || newsEnabled), checkTask == nil else { return }
        checkTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if UIApplication.shared.applicationState == .active {
                    await self.checkOnce()
                }
                do {
                    try await Task.sleep(for: .seconds(900))
                } catch { return }
            }
        }
    }

    private func checkOnce() async {
        guard !lookupInProgress, let coordinate = location?.coordinate else { return }
        lookupInProgress = true
        defer { lookupInProgress = false }
        // Neighborhood-level accuracy is sufficient for weather and reduces
        // the precision of coordinates sent to external weather services.
        let lat = (coordinate.latitude * 100).rounded() / 100
        let lon = (coordinate.longitude * 100).rounded() / 100

        if weatherEnabled {
            await checkOfficialWarnings(latitude: lat, longitude: lon)
            await checkRainForecast(latitude: lat, longitude: lon)
        }
        if newsEnabled, let locality, !locality.isEmpty {
            await checkLocalHeadlines(city: locality, state: state ?? "")
        }
    }

    private func fetch(_ url: URL, nws: Bool = false) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        if nws {
            request.setValue("JARVIS-AURA/1.0 (personal weather notifications)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private struct WarningFeed: Decodable {
        struct Feature: Decodable {
            let id: String?
            let properties: Warning
        }
        struct Warning: Decodable {
            let event: String?
            let severity: String?
            let headline: String?
        }
        let features: [Feature]
    }

    private func checkOfficialWarnings(latitude: Double, longitude: Double) async {
        guard let url = URL(string: "https://api.weather.gov/alerts/active?point=\(latitude),\(longitude)") else { return }
        do {
            let data = try await fetch(url, nws: true)
            let warnings = try JSONDecoder().decode(WarningFeed.self, from: data)
            for feature in warnings.features {
                let event = feature.properties.event ?? "Weather warning"
                let severity = feature.properties.severity ?? ""
                let critical = severity == "Extreme" || severity == "Severe" ||
                    event.localizedCaseInsensitiveContains("thunderstorm warning") ||
                    event.localizedCaseInsensitiveContains("flood warning") ||
                    event.localizedCaseInsensitiveContains("tornado warning")
                guard critical else { continue }
                let id = feature.id ?? (event + (feature.properties.headline ?? ""))
                let key = "AuraNWS:" + id
                guard !UserDefaults.standard.bool(forKey: key) else { continue }
                UserDefaults.standard.set(true, forKey: key)
                onChime?("Important weather alert near your area: \(event). Check the official National Weather Service alert for details.")
                break // Never pile on multiple spoken warnings at once.
            }
            onStatus?("Checking official weather warnings every 15 minutes while AURA is active.")
        } catch {
            onStatus?("Weather updates need internet. I'll try again later.")
        }
    }

    private struct RainForecast: Decodable {
        struct Hourly: Decodable {
            let precipitation_probability: [Int?]?
            let weather_code: [Int?]?
        }
        let hourly: Hourly
    }

    private func checkRainForecast(latitude: Double, longitude: Double) async {
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        parts?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "hourly", value: "precipitation_probability,weather_code"),
            URLQueryItem(name: "forecast_hours", value: "3"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = parts?.url else { return }
        do {
            let data = try await fetch(url)
            let rain = try JSONDecoder().decode(RainForecast.self, from: data)
            let probabilities = rain.hourly.precipitation_probability ?? []
            let codes = rain.hourly.weather_code ?? []
            let thunder = codes.contains(where: { [95, 96, 99].contains($0 ?? -1) })
            let likelyRain = probabilities.contains(where: { ($0 ?? 0) >= 80 })
            guard (thunder || likelyRain),
                  Date().timeIntervalSince(lastRainChime) > 4 * 3600 else { return }
            lastRainChime = Date()
            onChime?(thunder
                ? "Heads up. The local forecast shows a possible thunderstorm within the next few hours."
                : "Heads up. Rain looks likely in your area within the next few hours.")
        } catch { /* NOAA warnings remain available even if forecast data fails. */ }
    }

    private func checkLocalHeadlines(city: String, state: String) async {
        // A city RSS search is not a proximity sensor. Never call a headline
        // 'right outside' the user's home or claim its location was verified.
        var parts = URLComponents(string: "https://news.google.com/rss/search")
        parts?.queryItems = [
            URLQueryItem(name: "q", value: "\"\(city)\" \(state) (warning OR evacuation OR fire OR flood OR storm OR emergency OR closure OR accident) when:1d"),
            URLQueryItem(name: "hl", value: "en-US"),
            URLQueryItem(name: "gl", value: "US"),
            URLQueryItem(name: "ceid", value: "US:en")
        ]
        guard let url = parts?.url else { return }
        do {
            let data = try await fetch(url)
            let feed = AuraNewsFeedParser.parse(data)
            // Baseline the existing headlines. Only chime for newly published
            // city-level safety headlines, not a backlog on first launch.
            if !newsSeeded {
                seenNews.formUnion(feed.map(\.title))
                newsSeeded = true
                onStatus?("Watching for new city-area safety headlines while AURA is active.")
                return
            }
            for article in feed {
                guard !seenNews.contains(article.title) else { continue }
                seenNews.insert(article.title)
                guard article.date.map({ Date().timeIntervalSince($0) < 7200 }) ?? false else { continue }
                let title = article.title
                let triggers = ["evacuation", "tornado", "flood", "wildfire", "emergency",
                                "shelter", "road closed", "major crash", "thunderstorm warning"]
                guard triggers.contains(where: { title.localizedCaseInsensitiveContains($0) }) else { continue }
                onChime?("New headline for the \(city) area: \(title). The exact distance and details haven't been verified.")
                break
            }
            if seenNews.count > 300 { seenNews.removeAll(); newsSeeded = false }
        } catch {
            onStatus?("Nearby news couldn't be checked right now.")
        }
    }
}

private final class AuraNewsFeedParser: NSObject, XMLParserDelegate {
    struct Article {
        var title: String
        var date: Date?
    }
    private var articles: [Article] = []
    private var insideItem = false
    private var element = ""
    private var value = ""
    private var title = ""
    private var dateString = ""

    static func parse(_ data: Data) -> [Article] {
        let handler = AuraNewsFeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = handler
        _ = parser.parse()
        return handler.articles
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "item" {
            insideItem = true
            title = ""
            dateString = ""
        }
        element = elementName
        value = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideItem { value += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if insideItem {
            if elementName == "title" { title = value }
            if elementName == "pubDate" { dateString = value }
            if elementName == "item" {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
                if !title.isEmpty {
                    articles.append(Article(title: title, date: formatter.date(from: dateString)))
                }
                insideItem = false
            }
        }
        element = ""
        value = ""
    }
}
