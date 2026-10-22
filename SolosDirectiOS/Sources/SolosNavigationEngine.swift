import Foundation
import MapKit
import CoreLocation
import AVFoundation
import UIKit
import Combine

@MainActor
final class SolosNavigationEngine: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var address = ""
    @Published private(set) var status = "Enter a destination and tap START NAVIGATION."
    @Published private(set) var active = false
    @Published private(set) var instruction = "ENTER DESTINATION"
    @Published private(set) var remaining = "—"
    @Published private(set) var eta = "—"
    @Published private(set) var nextTurn = "—"
    @Published private(set) var destination = "—"
    @Published private(set) var route: MKRoute?
    @Published private(set) var position: CLLocationCoordinate2D?
    @Published private(set) var target: CLLocationCoordinate2D?
    @Published var voiceEnabled = true
    private let gps = CLLocationManager()
    private let speaker = AVSpeechSynthesizer()
    private var steps: [MKRoute.Step] = []
    private var currentIndex = 0
    private var lastSpoken = ""
    private var lastAnnouncedDistance = Double.infinity
    private var recalculationAt = Date.distantPast
    var onUpdate: (() -> Void)?
    override init() {
        super.init()
        gps.delegate = self
        gps.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        gps.distanceFilter = 7
    }
    func start() async {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { status = "Enter an address first."; return }
        gps.requestWhenInUseAuthorization()
        guard CLLocationManager.locationServicesEnabled() else {
            status = "Turn on iPhone Location Services."; return
        }
        if gps.authorizationStatus == .denied || gps.authorizationStatus == .restricted {
            status = "Allow location access in iPhone Settings."; return
        }
        gps.startUpdatingLocation()
        guard let origin = gps.location?.coordinate else {
            status = "Waiting for GPS fix. Try START again outdoors."; return
        }
        status = "Searching Apple Maps for " + text + "..."
        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            request.region = MKCoordinateRegion(center: origin, latitudinalMeters: 60000, longitudinalMeters: 60000)
            let result = try await MKLocalSearch(request:request).start()
            guard let place = result.mapItems.first else {
                status = "Address not found. Include city or ZIP code."; return
            }
            destination = place.name ?? text
            target = place.placemark.coordinate
            try await calculate(from:origin,to:place)
        } catch {
            status = "Map search failed: " + error.localizedDescription
        }
    }
    private func calculate(from origin:CLLocationCoordinate2D,to destinationItem:MKMapItem) async throws {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate:origin))
        request.destination = destinationItem
        request.transportType = .automobile
        let result = try await MKDirections(request:request).calculate()
        guard let best = result.routes.first else {
            status = "No driving route found."; return
        }
        route = best
        steps = best.steps.filter { !$0.instructions.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }
        currentIndex = 0
        lastSpoken = ""
        lastAnnouncedDistance = .infinity
        active = true
        status = "Navigating to " + destination
        updateProgress(at: CLLocation(latitude:origin.latitude,longitude:origin.longitude), announce:true)
    }
    func stop() {
        active = false
        gps.stopUpdatingLocation()
        speaker.stopSpeaking(at:.immediate)
        status = "Navigation stopped."
        route = nil
        steps = []
        instruction = "ENTER DESTINATION"
        onUpdate?()
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
    func locationManager(_ manager: CLLocationManager,didUpdateLocations locations:[CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        position = location.coordinate
        if active { updateProgress(at:location,announce:true) }
    }
    func locationManager(_ manager: CLLocationManager,didFailWithError error:Error) {
        status = "GPS: " + error.localizedDescription
    }
    private func updateProgress(at location:CLLocation,announce:Bool) {
        guard let route else { return }
        let finish = target.map { CLLocation(latitude:$0.latitude,longitude:$0.longitude) }
        let toFinish = finish.map { location.distance(from:$0) } ?? route.distance
        remaining = toFinish >= 1609.344
            ? String(format:"%.1f mi",toFinish/1609.344)
            : String(format:"%.0f ft",toFinish*3.28084)
        let expectedSpeed = max(2.0,location.speed >= 0 ? location.speed : route.distance/max(1,route.expectedTravelTime))
        let seconds = toFinish / expectedSpeed
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        eta = formatter.string(from:Date().addingTimeInterval(seconds))
        if toFinish < 35 {
            instruction = "YOU HAVE ARRIVED"
            nextTurn = "0 ft"
            if lastSpoken != instruction { say(instruction); lastSpoken = instruction }
            active = false
            onUpdate?()
            return
        }
        guard !steps.isEmpty else {
            instruction = "CONTINUE TO DESTINATION"
            onUpdate?()
            return
        }
        // Apple Maps route steps are ordered; advance only when the user is
        // physically close to the step's endpoint, not on a timer.
        while currentIndex < steps.count - 1 {
            let step = steps[currentIndex]
            let points = step.polyline.points()
            guard step.polyline.pointCount > 0 else { currentIndex += 1; continue }
            let endpoint = MKMapPoint(x:points[step.polyline.pointCount-1].x,
                                     y:points[step.polyline.pointCount-1].y)
            let coordinate = endpoint.coordinate
            let meters = location.distance(from:CLLocation(latitude:coordinate.latitude,longitude:coordinate.longitude))
            if meters < 22 { currentIndex += 1; lastSpoken = ""; lastAnnouncedDistance = .infinity }
            else { break }
        }
        let step = steps[currentIndex]
        instruction = step.instructions.uppercased()
        let pointCount = step.polyline.pointCount
        var meters = step.distance
        if pointCount > 0 {
            let endpoint = step.polyline.points()[pointCount-1].coordinate
            meters = location.distance(from:CLLocation(latitude:endpoint.latitude,longitude:endpoint.longitude))
        }
        nextTurn = meters >= 1609.344 ? String(format:"%.1f MI",meters/1609.344)
                 : String(format:"%.0f FT",meters*3.28084)
        if announce && (lastSpoken != instruction || (meters < 120 && lastAnnouncedDistance > 120)) {
            let prefix = meters > 40 ? "In " + nextTurn.lowercased() + ", " : ""
            say(prefix + step.instructions)
            lastSpoken = instruction
            lastAnnouncedDistance = meters
        }
        onUpdate?()
    }
    private func say(_ words:String) {
        guard voiceEnabled else { return }
        speaker.stopSpeaking(at:.immediate)
        let speech = AVSpeechUtterance(string:words)
        speech.voice = AVSpeechSynthesisVoice(language:"en-US")
        speech.rate = 0.49
        speaker.speak(speech)
    }
}
