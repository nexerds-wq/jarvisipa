import Foundation
import CoreLocation
import UserNotifications
import Combine

// Supplemental public reports, not a substitute for official emergency alerts.
struct JarvisEarthquakeEvent: Identifiable {
    let id: String
    let title: String
    let magnitude: Double
    let distanceKM: Double
    let date: Date
    let url: URL
}

@MainActor
final class JarvisEarthquakeMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var events: [JarvisEarthquakeEvent] = []
    @Published private(set) var status = "Enable location to check USGS earthquake reports"
    @Published private(set) var checkedAt: Date?
    @Published private(set) var travelMode = false
    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var lastRequest = Date.distantPast
    private var notified = Set<String>()
    private var fetching = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func setTravelMode(_ enabled: Bool) {
        travelMode = enabled
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else {
            status = "Significant location monitoring is not available on this device"
            return
        }
        if enabled {
            if manager.authorizationStatus == .authorizedAlways {
                manager.startMonitoringSignificantLocationChanges()
                status = "Travel monitoring enabled when iOS delivers location updates"
            } else {
                manager.requestAlwaysAuthorization()
                status = "Allow Always location access in Settings for travel monitoring"
            }
        } else {
            manager.stopMonitoringSignificantLocationChanges()
            status = "Travel monitoring off"
        }
    }

    func refresh() {
        if let lastLocation {
            Task { await check(at: lastLocation, force: true) }
        } else {
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways {
            if travelMode { manager.startMonitoringSignificantLocationChanges() }
            manager.requestLocation()
        } else if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestLocation()
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            status = "Location access disabled"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last, fix.horizontalAccuracy >= 0 else { return }
        lastLocation = fix
        Task { await check(at: fix, force: false) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "Location unavailable: \(error.localizedDescription)"
    }

    private func check(at fix: CLLocation, force: Bool) async {
        guard !fetching else { return }
        guard force || Date().timeIntervalSince(lastRequest) >= 900 else { return }
        fetching = true
        lastRequest = Date()
        defer { fetching = false }

        var query = URLComponents(string: "https://earthquake.usgs.gov/fdsnws/event/1/query")!
        query.queryItems = [
            URLQueryItem(name: "format", value: "geojson"),
            URLQueryItem(name: "latitude", value: String(fix.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(fix.coordinate.longitude)),
            URLQueryItem(name: "maxradiuskm", value: "250"),
            URLQueryItem(name: "starttime", value: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86400))),
            URLQueryItem(name: "minmagnitude", value: "2.5"),
            URLQueryItem(name: "orderby", value: "time"),
            URLQueryItem(name: "limit", value: "25")
        ]
        guard let url = query.url else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let features = json?["features"] as? [[String: Any]] ?? []
            var found: [JarvisEarthquakeEvent] = []
            for feature in features {
                let properties = feature["properties"] as? [String: Any] ?? [:]
                let geometry = feature["geometry"] as? [String: Any] ?? [:]
                let coords = geometry["coordinates"] as? [Double] ?? []
                guard coords.count >= 2,
                      let magnitude = properties["mag"] as? Double,
                      let ms = properties["time"] as? Double,
                      let linkText = properties["url"] as? String,
                      let link = URL(string: linkText),
                      link.scheme == "https" else { continue }
                let epicenter = CLLocation(latitude: coords[1], longitude: coords[0])
                let distance = fix.distance(from: epicenter) / 1000
                guard distance <= 250 else { continue }
                let id = feature["id"] as? String ?? link.absoluteString
                found.append(JarvisEarthquakeEvent(
                    id: id, title: properties["place"] as? String ?? "Reported earthquake",
                    magnitude: magnitude, distanceKM: distance,
                    date: Date(timeIntervalSince1970: ms / 1000), url: link
                ))
            }
            events = found.sorted { $0.date > $1.date }
            checkedAt = Date()
            status = "USGS checked • reports are delayed and may be revised"
            for event in found where event.magnitude >= 4.0 && event.distanceKM <= 100 &&
                Date().timeIntervalSince(event.date) < 3600 && !notified.contains(event.id) {
                notified.insert(event.id)
                let message = UNMutableNotificationContent()
                message.title = "USGS reported M\(String(format: "%.1f", event.magnitude)) earthquake"
                message.body = "\(Int(event.distanceKM.rounded())) km away • \(event.title). Check official guidance."
                message.sound = .default
                UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: "jarvis-usgs-\(event.id)", content: message, trigger: nil)
                ) { _ in }
            }
        } catch {
            status = "USGS check unavailable: \(error.localizedDescription)"
        }
    }
}
