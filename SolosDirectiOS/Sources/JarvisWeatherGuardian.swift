import Foundation
import CoreLocation
import UserNotifications
import UIKit
import Combine

/// Free public sources: NWS active warnings and Open-Meteo short-range forecasts.
/// Checks while the app is running; iOS does not guarantee uninterrupted polling in background.
@MainActor final class JarvisWeatherGuardian: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var banner: String = ""
    @Published private(set) var status = "Waiting for location permission"
    @Published private(set) var temperature: String = "—"
    @Published private(set) var locationReady = false
    @Published private(set) var nearbyCity = ""
    @Published private(set) var lastChecked: Date?
    private let location = CLLocationManager()
    private var timer: Timer?
    private var checking = false
    private var delivered = Set<String>()
    private var activeUntil = Date.distantPast
    private var lastCoordinates: CLLocationCoordinate2D?
    private let geocoder = CLGeocoder()
    private var lastGeocodedAt = Date.distantPast

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    func start() {
        UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.badge,.sound]) { _,_ in }
        if location.authorizationStatus == .notDetermined {
            location.requestWhenInUseAuthorization()
        } else if location.authorizationStatus == .authorizedWhenInUse || location.authorizationStatus == .authorizedAlways {
            locationReady = true
            location.requestLocation()
        } else {
            status = "Location permission required in iPhone Settings"
        }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval:90,repeats:true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }
    func stop() { timer?.invalidate(); timer = nil }
    func locationManagerDidChangeAuthorization(_ manager:CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            locationReady = true
            manager.requestLocation()
        }
    }
    func locationManager(_ manager:CLLocationManager,didUpdateLocations locations:[CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        lastCoordinates = coordinate
        if Date().timeIntervalSince(lastGeocodedAt) > 900 {
            lastGeocodedAt = Date()
            geocoder.reverseGeocodeLocation(CLLocation(latitude:coordinate.latitude,
                                                       longitude:coordinate.longitude)) { [weak self] places,_ in
                Task { @MainActor in
                    guard let place = places?.first else { return }
                    let city = place.locality ?? place.subAdministrativeArea ?? ""
                    let region = place.administrativeArea ?? ""
                    self?.nearbyCity = [city,region].filter { !$0.isEmpty }.joined(separator:", ")
                }
            }
        }
        Task { await check(coordinate) }
    }
    func locationManager(_ manager:CLLocationManager,didFailWithError error:Error) {
        status = "GPS: " + error.localizedDescription
    }
    func refresh() {
        location.requestLocation()
        if let lastCoordinates { Task { await check(lastCoordinates) } }
    }
    private func json(_ url:URL, nws:Bool = false) async throws -> [String:Any] {
        var request = URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:15)
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        if nws { request.setValue("JarvisSolosHUD/1.0 (personal weather safety assistant)",forHTTPHeaderField:"User-Agent") }
        let (data,response) = try await URLSession.shared.data(for:request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return (try JSONSerialization.jsonObject(with:data)) as? [String:Any] ?? [:]
    }
    private func check(_ coordinate:CLLocationCoordinate2D) async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        let lat = String(format:"%.4f",coordinate.latitude)
        let lon = String(format:"%.4f",coordinate.longitude)
        var candidates:[(String,String,String,Int)] = []
        var successes = 0
        if let url = URL(string:"https://api.weather.gov/alerts/active?point=\(lat),\(lon)") {
            do {
                let data = try await json(url,nws:true)
                successes += 1
                for feature in (data["features"] as? [[String:Any]] ?? []) {
                    let p = feature["properties"] as? [String:Any] ?? [:]
                    let event = p["event"] as? String ?? "Weather alert"
                    let severity = p["severity"] as? String ?? ""
                    let id = p["id"] as? String ?? event
                    let headline = p["headline"] as? String ?? event
                    let urgent = ["Tornado Warning","Hurricane Warning","Extreme Wind Warning","Flash Flood Warning","Severe Thunderstorm Warning","Storm Surge Warning","Tsunami Warning"].contains(event)
                    let priority = urgent ? 100 : (severity == "Severe" || severity == "Extreme" ? 85 : 60)
                    candidates.append((id,event,headline,priority))
                }
            } catch { status = "NWS unavailable: " + error.localizedDescription }
        }
        // 15-minute rain is a forecast, NOT live radar or lightning strike detection.
        let forecast = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code&minutely_15=precipitation&forecast_minutely_15=4&timezone=auto"
        if let url = URL(string:forecast) {
            do {
                let data = try await json(url)
                successes += 1
                if let current = data["current"] as? [String:Any],
                   let degrees = current["temperature_2m"] as? Double {
                    temperature = "\(Int(degrees.rounded()))°C"
                }
                if let minutely = data["minutely_15"] as? [String:Any],
                   let precipitation = minutely["precipitation"] as? [Double] {
                    if let index = precipitation.prefix(4).firstIndex(where:{$0 >= 0.2}) {
                        let minutes = index * 15
                        candidates.append(("rain-\(Int(Date().timeIntervalSince1970/3600))","RAIN FORECAST","Rain possible in about \(minutes)–\(minutes+15) minutes (model forecast)",30))
                    }
                }
            } catch { if successes == 0 { status = "Weather network unavailable" } }
        }
        lastChecked = Date()
        if successes > 0 { status = "Weather checked • \(Date().formatted(date:.omitted,time:.shortened))" }
        if let best = candidates.max(by:{$0.3 < $1.3}) {
            banner = best.1.uppercased() + " • " + best.2
            activeUntil = Date().addingTimeInterval(best.3 >= 60 ? 1800 : 900)
            if !delivered.contains(best.0) {
                delivered.insert(best.0)
                let content = UNMutableNotificationContent()
                content.title = best.1
                content.body = best.2
                content.sound = .default
                let request = UNNotificationRequest(identifier:"jarvis-weather-"+UUID().uuidString,
                                                    content:content,trigger:nil)
                UNUserNotificationCenter.current().add(request,withCompletionHandler:{ _ in })
            }
        } else if Date() > activeUntil {
            banner = ""
        }
    }
    func overlay(_ original:UIImage) -> UIImage {
        guard !banner.isEmpty else { return original }
        let renderer = UIGraphicsImageRenderer(size:CGSize(width:428,height:240))
        return renderer.image { ctx in
            original.draw(in:CGRect(x:0,y:0,width:428,height:240))
            UIColor(red:0.40,green:0.03,blue:0.03,alpha:0.97).setFill()
            ctx.cgContext.fill(CGRect(x:0,y:0,width:428,height:85))
            UIColor.white.setFill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            (banner as NSString).draw(in:CGRect(x:12,y:8,width:404,height:74),
                withAttributes:[.font:UIFont.systemFont(ofSize:22,weight:.heavy),
                                .foregroundColor:UIColor.white,
                                .paragraphStyle:paragraph])
        }
    }
}
