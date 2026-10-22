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
    private var waitingForFirstGPS = false
    private var dashboardBackgroundEnabled = false
    private var recalculating = false
    private var lastBackgroundTick = Date.distantPast
    private var lastHUDUpdate = Date.distantPast
    private var announcedStep = -1
    private var lastThreshold = Int.max
    var onBackgroundTick: (() -> Void)?
    var onUpdate: (() -> Void)?
    override init() {
        super.init()
        gps.delegate = self
        gps.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        gps.distanceFilter = 7
        gps.activityType = .automotiveNavigation
        gps.pausesLocationUpdatesAutomatically = false
        gps.showsBackgroundLocationIndicator = true
    }
    // User-controlled screen-off OLED refresh. Uses location background mode
    // while connected so the HUD can redraw steps/time without the app visible.
    // This consumes additional battery and stops if iOS terminates the app.
    func enableBackgroundDashboard(_ enable: Bool) {
        dashboardBackgroundEnabled = enable
        if enable {
            gps.requestWhenInUseAuthorization()
            if gps.authorizationStatus == .authorizedWhenInUse || gps.authorizationStatus == .authorizedAlways {
                gps.allowsBackgroundLocationUpdates = true
                gps.startUpdatingLocation()
            } else {
                status = "Allow location access to enable the screen-off dashboard."
            }
        } else if !active {
            gps.stopUpdatingLocation()
            gps.allowsBackgroundLocationUpdates = false
        }
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
            waitingForFirstGPS = true
            gps.requestLocation()
            status = "Waiting for accurate GPS. Route will start automatically..."
            return
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
        if gps.authorizationStatus == .authorizedWhenInUse || gps.authorizationStatus == .authorizedAlways {
            gps.allowsBackgroundLocationUpdates = true
            gps.startUpdatingLocation()
        }
        prepareAudioForSpeech()
        steps = best.steps.filter { !$0.instructions.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }
        currentIndex = 0
        lastSpoken = ""
        lastAnnouncedDistance = .infinity
        announcedStep = -1
        lastThreshold = Int.max
        active = true
        status = "Navigating to " + destination
        updateProgress(at: CLLocation(latitude:origin.latitude,longitude:origin.longitude), announce:true)
    }
    func stop() {
        active = false
        waitingForFirstGPS = false
        if !dashboardBackgroundEnabled {
            gps.stopUpdatingLocation()
            gps.allowsBackgroundLocationUpdates = false
        }
        speaker.stopSpeaking(at:.immediate)
        status = "Navigation stopped."
        route = nil
        steps = []
        instruction = "ENTER DESTINATION"
        onUpdate?()
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            if dashboardBackgroundEnabled || active {
                manager.allowsBackgroundLocationUpdates = true
            }
            manager.startUpdatingLocation()
        }
    }
    func locationManager(_ manager: CLLocationManager,didUpdateLocations locations:[CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        position = location.coordinate
        if waitingForFirstGPS {
            waitingForFirstGPS = false
            Task { await self.start() }
        }
        if active {
            updateProgress(at:location,announce:true)
        }
        if active || dashboardBackgroundEnabled {
            if Date().timeIntervalSince(lastBackgroundTick) > 55 {
                lastBackgroundTick = Date()
                onBackgroundTick?()
            }
        }
    }
    func locationManager(_ manager: CLLocationManager,didFailWithError error:Error) {
        status = "GPS: " + error.localizedDescription
    }
    private func updateProgress(at location:CLLocation, announce:Bool) {
        guard let route else { return }
        let destinationLocation = target.map { CLLocation(latitude:$0.latitude,longitude:$0.longitude) }
        let toDestination = destinationLocation.map { location.distance(from:$0) } ?? route.distance
        if toDestination < 28 {
            instruction = "YOU HAVE ARRIVED"
            nextTurn = "0 FT"
            remaining = "0 FT"
            eta = DateFormatter.localizedString(from:Date(),dateStyle:.none,timeStyle:.short)
            if lastSpoken != instruction { say("You have arrived at your destination."); lastSpoken = instruction }
            active = false
            if !dashboardBackgroundEnabled {
                gps.stopUpdatingLocation()
                gps.allowsBackgroundLocationUpdates = false
            }
            onUpdate?()
            return
        }

        // Project location onto the actual route polyline, not the straight-line
        // distance to destination. This makes remaining distance and ETA road-based.
        let projection = closestPoint(to:location.coordinate, on:route.polyline)
        if projection.offRoute > 100 && Date().timeIntervalSince(recalculationAt) > 45 && !recalculating,
           let target {
            recalculationAt = Date()
            recalculating = true
            status = "Off route. Recalculating..."
            let destinationItem = MKMapItem(placemark:MKPlacemark(coordinate:target))
            Task {
                defer { recalculating = false }
                do { try await calculate(from:location.coordinate,to:destinationItem) }
                catch { status = "Rerouting failed: " + error.localizedDescription }
            }
            return
        }

        let remainingMeters = max(toDestination, route.distance * (1 - projection.fraction))
        remaining = formatDistance(remainingMeters)
        let routeSeconds = route.expectedTravelTime * max(0.01, remainingMeters / max(1,route.distance))
        let speedSeconds = location.speed > 2 ? remainingMeters / location.speed : routeSeconds
        let seconds = max(60, min(routeSeconds * 1.4, max(routeSeconds * 0.75, speedSeconds)))
        eta = DateFormatter.localizedString(from:Date().addingTimeInterval(seconds),dateStyle:.none,timeStyle:.short)

        guard !steps.isEmpty else {
            instruction = "CONTINUE TO DESTINATION"
            nextTurn = remaining
            onUpdate?()
            return
        }

        // Choose a route step by where the user is on the route. This prevents
        // indefinitely getting stuck on a turn already passed.
        var candidate = currentIndex
        var bestDistance = Double.infinity
        for i in currentIndex..<steps.count {
            let step = steps[i]
            guard step.polyline.pointCount > 0 else { continue }
            let p = closestPoint(to:location.coordinate,on:step.polyline)
            if p.offRoute < bestDistance {
                candidate = i
                bestDistance = p.offRoute
            }
            if p.offRoute < 30 { break }
        }
        if candidate > currentIndex {
            currentIndex = candidate
            announcedStep = -1
            lastThreshold = Int.max
        }
        let step = steps[currentIndex]
        instruction = step.instructions.uppercased()
        let pointCount = step.polyline.pointCount
        var meters = step.distance
        if pointCount > 0 {
            let endpoint = step.polyline.points()[pointCount - 1].coordinate
            meters = location.distance(from:CLLocation(latitude:endpoint.latitude,longitude:endpoint.longitude))
        }
        if meters < 25 && currentIndex < steps.count - 1 {
            currentIndex += 1
            announcedStep = -1
            lastThreshold = Int.max
        }
        nextTurn = formatDistance(meters).uppercased()

        // Say each new turn, plus advance warnings at about 500 / 150 / 50 m.
        let threshold = meters < 50 ? 0 : meters < 150 ? 1 : meters < 500 ? 2 : 3
        if announce && (announcedStep != currentIndex || threshold < lastThreshold) {
            let prefix = meters > 35 ? "In " + formatDistance(meters) + ", " : ""
            say(prefix + steps[currentIndex].instructions)
            announcedStep = currentIndex
            lastThreshold = threshold
        }
        if Date().timeIntervalSince(lastHUDUpdate) > 2.0 {
            lastHUDUpdate = Date()
            onUpdate?()
        }
    }

    private func closestPoint(to coordinate:CLLocationCoordinate2D,on polyline:MKPolyline) -> (fraction:Double,offRoute:Double) {
        guard polyline.pointCount > 1 else { return (0,Double.infinity) }
        let points = polyline.points()
        let user = MKMapPoint(coordinate)
        var total = 0.0
        var closest = Double.infinity
        var distanceAlong = 0.0
        var covered = 0.0
        for index in 0..<(polyline.pointCount - 1) {
            let a = points[index]
            let b = points[index+1]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let lengthSq = dx*dx + dy*dy
            if lengthSq <= 0 { continue }
            let t = max(0,min(1,((user.x-a.x)*dx + (user.y-a.y)*dy)/lengthSq))
            let px = a.x + dx*t
            let py = a.y + dy*t
            let distance = MKMapPoint(x:px,y:py).distance(to:user)
            let length = sqrt(lengthSq)
            if distance < closest {
                closest = distance
                distanceAlong = covered + length*t
            }
            covered += length
        }
        total = covered
        return (fraction:total > 0 ? max(0,min(1,distanceAlong/total)) : 0,
                offRoute:closest)
    }

    private func formatDistance(_ meters:Double) -> String {
        meters >= 1609.344 ? String(format:"%.1f mi",meters/1609.344)
            : String(format:"%.0f ft",meters*3.28084)
    }

    private func prepareAudioForSpeech() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback,mode:.spokenAudio,options:[.duckOthers])
            try session.setActive(true)
        } catch {
            status = "Audio setup: " + error.localizedDescription
        }
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
