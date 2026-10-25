import Foundation
import Combine
import SwiftUI
import AVFoundation
import Speech
import CoreLocation
import CoreMotion
import CoreBluetooth
import FoundationModels

final class SolosPhoneController: NSObject, ObservableObject, CLLocationManagerDelegate, CBCentralManagerDelegate {
    @Published var aiStatus = "Ready to use on-device JARVIS"
    @Published var aiAnswer = "Ask JARVIS a question or start listening."
    @Published var transcribed = ""
    var onHUDVoiceCommand: ((String) -> Bool)?
    @Published var voiceStatus = "Not listening"
    @Published private(set) var microphoneLevel: Double = 0
    @Published private(set) var userVoiceActive = false
    @Published var listening = false
    @Published var discoveredBLE = [String]()
    @Published var bleState = "Bluetooth scan not started"
    @Published var steps = "–"
    @Published var distance = "–"
    @Published var battery = "–"
    @Published var motionStatus = "Checking the motion sensor..."
    @Published var locationStatus = "Location permission not checked"
    @Published var speed = "–"
    @Published var coordinates = "GPS not ready"
    @Published var now = Date()

    let accessory = SolosClassicManager()
    private let location = CLLocationManager()
    private let pedometer = CMPedometer()
    private var central: CBCentralManager?
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    // Removing a tap that was never installed can raise an Obj-C AVFAudio
    // exception (not caught by Swift do/catch). Captions take mic ownership
    // often, including before the wake recognizer has ever started.
    private var wakeAudioTapInstalled = false
    private let meterLock = NSLock()
    private var lastMeterPublish = Date.distantPast
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechTask: SFSpeechRecognitionTask?
    private let recognitionRequestLock = NSLock()
    private var heardWake = false
    private var lastQuestion = ""
    private var continuousWakeWanted = false
    private var musicPlaybackActive = false
    private var hudCaptionsActive = false
    private var awaitingSpeechCompletion = false
    private var recognitionGeneration = 0
    private var restartScheduled = false
    private var startingRecognition = false
    private var speechStartedAt = Date.distantPast
    private var questionSilenceWork: DispatchWorkItem?
    private var pendingVoiceQuestion = ""
    private var awaitingFollowUp = false
    private var followUpExpiresAt = Date.distantPast
    private var recognizerStartedAt = Date.distantPast
    private var audioObservers: [NSObjectProtocol] = []
    private var lockWatchdog: Timer?
    private var timer: Timer?
    private var lastPedometerDay = Calendar.current.startOfDay(for: Date())
    private var lastDashboardGPSUIAt = Date.distantPast
    private var asking = false

    override init() {
        super.init()
        accessory.onSpeechCompleted = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                // didCancel can be delivered for an earlier utterance after
                // another utterance starts. Do not tear down the new answer.
                guard !self.accessory.isSpeaking else { return }
                self.awaitingSpeechCompletion = false
                guard self.continuousWakeWanted else { return }
                self.voiceStatus = "Answer finished — restoring Hey Jarvis listening"
                self.scheduleWakeRearm(after:0.6)
            }
        }
        // Observe audio interruptions and route changes rather than showing
        // "Listening" indefinitely after iOS has stopped microphone capture.
        let center = NotificationCenter.default
        audioObservers.append(center.addObserver(forName:AVAudioSession.interruptionNotification,
            object:AVAudioSession.sharedInstance(),queue:.main) { [weak self] note in
            guard let self else { return }
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.began.rawValue {
                let rearm = self.continuousWakeWanted
                self.stopListening()
                self.continuousWakeWanted = rearm
                self.voiceStatus = "iOS interrupted microphone audio; waiting for it to end"
            } else if raw == AVAudioSession.InterruptionType.ended.rawValue {
                self.resumeWakeIfNeeded()
            }
        })
        audioObservers.append(center.addObserver(forName:AVAudioSession.routeChangeNotification,
            object:AVAudioSession.sharedInstance(),queue:.main) { [weak self] _ in
            guard let self else { return }
            if self.continuousWakeWanted && self.listening &&
               !self.awaitingSpeechCompletion && !self.accessory.isSpeaking &&
               !self.audioEngine.isRunning {
                self.voiceStatus = "Audio route changed; reconnecting microphone"
                self.restartRecognitionSoon()
            }
        })
        audioObservers.append(center.addObserver(forName:Notification.Name.AVAudioEngineConfigurationChange,
            object:audioEngine,queue:.main) { [weak self] _ in
            guard let self, self.continuousWakeWanted, self.listening,
                  !self.awaitingSpeechCompletion, !self.accessory.isSpeaking else { return }
            self.voiceStatus = "Audio engine configuration changed; restarting"
            self.restartRecognitionSoon()
        })
        lockWatchdog = Timer.scheduledTimer(withTimeInterval:5,repeats:true) { [weak self] _ in
            guard let self, self.continuousWakeWanted else { return }
            // Speech synthesis can finish, fail, or be interrupted without
            // delivering its completion delegate callback. Never leave
            // continuous wake blocked forever by awaitingSpeechCompletion.
            if self.awaitingSpeechCompletion && !self.asking &&
               !self.accessory.isSpeaking &&
               Date().timeIntervalSince(self.speechStartedAt) > 1.5 {
                self.awaitingSpeechCompletion = false
                self.voiceStatus = "Recovered missed speech-finished callback"
            }
            if self.listening && !self.audioEngine.isRunning {
                self.voiceStatus = "Microphone stopped; trying to restore listening"
                self.restartRecognitionSoon()
            } else if !self.listening && !self.asking &&
                        !self.awaitingSpeechCompletion && !self.accessory.isSpeaking {
                self.resumeWakeIfNeeded()
            }
        }
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // Dashboard GPS is a glanceable status, not turn-by-turn tracking.
        // Avoid a permanent per-second GPS stream and full SwiftUI refreshes.
        location.distanceFilter = 25
        location.pausesLocationUpdatesAutomatically = true
        central = CBCentralManager(delegate: self, queue: nil)
        // A once-per-second @Published clock forced SwiftUI to rebuild the
        // entire dashboard, previews and encoder 60 times each minute.
        // The UI shows minute-level time; 15s is sufficient and keeps
        // midnight and battery updates prompt without constant CPU churn.
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let device = self else { return }
            let current = Date()
            device.now = current
            let today = Calendar.current.startOfDay(for: current)
            if today != device.lastPedometerDay {
                // Automatic midnight reset: query new day's steps instead of keeping yesterday.
                device.lastPedometerDay = today
                device.steps = "0"
                device.distance = "0.00 mi"
                device.refreshSensors()
            }
            let level = UIDevice.current.batteryLevel
            let value = level >= 0 ? String(format: "%.0f%%", level * 100) : "N/A"
            if device.battery != value { device.battery = value }
        }
    }
    var clock: String {
        DateFormatter.localizedString(from: now, dateStyle: .none, timeStyle: .short)
    }
    var dateLine: String {
        DateFormatter.localizedString(from: now, dateStyle: .medium, timeStyle: .none)
    }
    var dashboard: String {
        "\(clock)  \(DateFormatter.localizedString(from: now, dateStyle: .short, timeStyle: .none))\nSTEPS \(steps)  DIST \(distance)\nBAT \(battery)  SPEED \(speed)\n\(coordinates)"
    }
    func refreshSensors() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        battery = level >= 0 ? String(format: "%.0f%%", level * 100) : "N/A"

        location.requestWhenInUseAuthorization()
        refreshLocationPermission()

        guard CMPedometer.isStepCountingAvailable() else {
            steps = "N/A"
            distance = "N/A"
            motionStatus = "Step counter unavailable on this device."
            return
        }
        let start = Calendar.current.startOfDay(for: Date())
        lastPedometerDay = start
        motionStatus = "Reading steps since midnight..."
        pedometer.stopUpdates()
        pedometer.queryPedometerData(from: start, to: Date()) { [weak self] data, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.updatePedometer(data: data, error: error)
            }
        }
        pedometer.startUpdates(from: start) { [weak self] data, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.updatePedometer(data: data, error: error)
            }
        }
    }
    // Re-query today's total without interrupting continuous pedometer monitoring.
    // Used during active GPS navigation so the steps HUD stays fresh with screen locked.
    func refreshStepsOnly() {
        let today = Calendar.current.startOfDay(for: Date())
        if today != lastPedometerDay {
            lastPedometerDay = today
            steps = "0"
            distance = "0.00 mi"
            refreshSensors()
            return
        }
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.queryPedometerData(from: today, to: Date()) { [weak self] data, error in
            DispatchQueue.main.async {
                self?.updatePedometer(data:data,error:error)
            }
        }
    }

    private func updatePedometer(data: CMPedometerData?, error: Error?) {
        if let error {
            motionStatus = "Steps unavailable: \(error.localizedDescription). Check Settings → Privacy → Motion & Fitness."
            return
        }
        guard let data else {
            motionStatus = "Waiting for today's step data."
            return
        }
        let stepValue = data.numberOfSteps.stringValue
        if steps != stepValue { steps = stepValue }
        let distanceValue = data.distance.map { String(format:"%.2f mi",$0.doubleValue / 1609.344) } ?? "N/A"
        if distance != distanceValue { distance = distanceValue }
        let newStatus = "Steps are from today's iPhone motion history."
        if motionStatus != newStatus { motionStatus = newStatus }
    }
    private func refreshLocationPermission() {
        guard CLLocationManager.locationServicesEnabled() else {
            locationStatus = "Location Services OFF in Settings"
            return
        }
        switch location.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationStatus = "GPS enabled. Move near a window/outdoors for a position."
            location.startUpdatingLocation()
        case .notDetermined:
            locationStatus = "Waiting for location permission..."
        case .denied, .restricted:
            locationStatus = "Location denied. Allow While Using App in Settings."
        @unknown default:
            locationStatus = "GPS authorization unknown"
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshLocationPermission()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let item = locations.last else { return }
        // SolosNavigationEngine owns the higher-frequency navigation GPS.
        // Updating 3 separate @Published properties on every stationary
        // dashboard fix caused unnecessary full-screen re-diffs.
        guard Date().timeIntervalSince(lastDashboardGPSUIAt) >= 10 else { return }
        lastDashboardGPSUIAt = Date()
        let gps = String(format:"GPS %.4f, %.4f",item.coordinate.latitude,item.coordinate.longitude)
        let accuracy = String(format:"GPS accuracy: ±%.0f m",max(0,item.horizontalAccuracy))
        let mph = item.speed >= 0 ? String(format:"%.1f mph",item.speed * 2.236936) : "–"
        if gps != coordinates { coordinates = gps }
        if accuracy != locationStatus { locationStatus = accuracy }
        if mph != speed { speed = mph }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        coordinates = "GPS: unavailable"
        locationStatus = error.localizedDescription
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bleState = central.state == .poweredOn ? "Bluetooth on; ready to scan" : "Bluetooth: \(central.state.rawValue)"
    }
    func scanBLE() {
        guard let central, central.state == .poweredOn else { bleState = "Enable Bluetooth in Settings"; return }
        discoveredBLE.removeAll()
        bleState = "Scanning BLE advertisements for 10 seconds..."
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.asyncAfter(deadline: .now()+10) { [weak self] in
            self?.central?.stopScan()
            self?.bleState = "Scan finished. BLE visibility alone does not provide RFCOMM display access."
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unnamed BLE device"
        let label = "\(name) (\(RSSI) dBm)"
        if !discoveredBLE.contains(label) { discoveredBLE.append(label) }
    }

    func ask(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { aiStatus = "Enter a question first."; return }
        guard !asking else { aiStatus = "JARVIS is answering another question."; return }
        asking = true
        aiStatus = "Thinking entirely on your iPhone..."
        aiAnswer = "YOU: \(trimmed)\n\nJARVIS THINKING..."
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.asking = false
                if self.continuousWakeWanted && !self.awaitingSpeechCompletion {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                        guard let self, self.continuousWakeWanted, !self.listening else { return }
                        self.startListening()
                    }
                }
            }
            // Live time/date never calls Foundation Models (or a remote LLM).
            // This must run before the AI availability check so the phone can
            // answer accurately even while Apple Intelligence is unavailable.
            if let clockAnswer = JarvisLiveClock.answer(for: trimmed) {
                self.deliverJarvisAnswer(clockAnswer, status:"Answered from iPhone clock (LIVE)")
                return
            }
            if #available(iOS 26.0, *) {
                guard SystemLanguageModel.default.isAvailable else {
                    self.deliverJarvisAnswer(
                        "I heard you, but Apple Intelligence is not ready. Please enable it and download its model in iPhone Settings.",
                        status:"Apple Intelligence unavailable — enable and download its model in Settings")
                    return
                }
                do {
                    // Foundation Models may reject or fail a session even when
                    // Apple Intelligence is switched on. Retry once with a fresh,
                    // minimal session and a clean question; never mask the cause.
                    let cleaned = trimmed.replacingOccurrences(
                        of: #"(?i)^\\s*(hey[ ,]*jarvis[ ,:!?.-]*)+"#,
                        with: "", options: .regularExpression
                    ).trimmingCharacters(in: .whitespacesAndNewlines)
                    let prompt = cleaned.isEmpty ? trimmed : cleaned
                    var response: String = ""
                    var answeredOnline = false
                    let systemInstructions = "Answer clearly in one or two short sentences. " +
                        JarvisLiveClock.modelTimeContext()
                    do {
                        // Stream partial tokens immediately; skip the second
                        // identical model retry which doubles failure latency.
                        response = try await self.fastOnDeviceAnswer(
                            prompt:prompt,instructions:systemInstructions)
                    } catch let modelError {
                        if UserDefaults.standard.bool(forKey:"jarvisWikipediaFallback") {
                            do {
                                response = try await Self.wikipediaAnswer(for:prompt)
                                answeredOnline = true
                            } catch let wikipediaError {
                                throw NSError(domain:"SolosJarvis.AI",code:2,userInfo:[
                                    NSLocalizedDescriptionKey:
                                        "Apple AI: " + Self.describeModelFailure(modelError)
                                        + ". Factual lookup: " + wikipediaError.localizedDescription
                                ])
                            }
                        } else {
                            throw NSError(domain:"SolosJarvis.AI",code:1,userInfo:[
                                NSLocalizedDescriptionKey:
                                    "Apple AI: " + Self.describeModelFailure(modelError)
                                    + ". The slow redundant second model pass was skipped."
                            ])
                        }
                    }
                    guard !response.isEmpty else {
                        throw NSError(domain:"SolosJarvis.AI",code:3,userInfo:[
                            NSLocalizedDescriptionKey:"The answer was empty. Try a shorter question."
                        ])
                    }
                    self.deliverJarvisAnswer(response, status: answeredOnline
                        ? "Answered from Wikipedia (ONLINE factual lookup)"
                        : "Answered locally with Apple Intelligence")
                } catch {
                    self.deliverJarvisAnswer(
                        "I heard your question, but I couldn't finish the answer. Please try again.",
                        status:"On-device JARVIS error: \(error.localizedDescription)")
                }
            } else {
                self.deliverJarvisAnswer("This version of Jarvis needs iOS 26 or newer for local AI.",
                                         status:"On-device AI requires iOS 26")
            }
        }
    }
    @MainActor
    private func fastOnDeviceAnswer(prompt:String,instructions:String) async throws -> String {
        let session = LanguageModelSession(instructions:instructions)
        // Apple recommends non-streaming responses in the background.
        // In foreground, deliver early token snapshots on the phone; send
        // to HUD and speak only after the complete reply is available.
        if UIApplication.shared.applicationState != .active {
            return try await session.respond(to:prompt).content
        }
        var answer = ""
        var lastUIUpdate = Date.distantPast
        let snapshots = session.streamResponse(to:prompt)
        for try await snapshot in snapshots {
            let content = snapshot.content
            guard !content.isEmpty else { continue }
            answer = content
            if Date().timeIntervalSince(lastUIUpdate) >= 0.16 {
                lastUIUpdate = Date()
                aiAnswer = content
                aiStatus = "JARVIS responding live..."
            }
        }
        return answer
    }

    // Shared for local clock, Apple AI and online factual answers.
    // All response paths use the same spoken audio and real glasses HUD
    // publication events, and preserve continuous microphone auto-rearm.
    private func deliverJarvisAnswer(_ response: String, status: String) {
        aiAnswer = response
        aiStatus = status
        if !(UserDefaults.standard.object(forKey:"jarvisSpeakAnswers") as? Bool ?? true) {
            let shouldResume = continuousWakeWanted
            stopListening()
            continuousWakeWanted = shouldResume
            voiceStatus = "Answer shown; spoken replies are disabled in Settings"
            if shouldResume { scheduleWakeRearm(after:0.3) }
            return
        }
        speakExternalReply(response)
    }

    // Shared audio handoff for built-in AI, Ollama replies, and the test
    // button. A TTS utterance must not compete with an active mic capture.
    func speakExternalReply(_ response: String, companion: Bool = false) {
        let shouldResume = continuousWakeWanted
        stopListening()
        continuousWakeWanted = shouldResume
        awaitingSpeechCompletion = true
        speechStartedAt = Date()
        voiceStatus = "Jarvis speaking — microphone paused"
        if companion { accessory.speakCompanion(response,style:"JARVIS") }
        else { accessory.speak(response) }
    }

    // iOS 26 Foundation Models can report an unhelpful NSError (-1).
    // Preserve the typed error and underlying error codes for troubleshooting.
    private static func describeModelFailure(_ error: Error) -> String {
        let ns = error as NSError
        var details = String(reflecting: error) + " [\(ns.domain):\(ns.code)]"
        if let typed = error as? LanguageModelSession.GenerationError {
            if let reason = typed.failureReason, !reason.isEmpty {
                details += " Reason: " + reason
            }
            if let suggestion = typed.recoverySuggestion, !suggestion.isEmpty {
                details += " Recovery: " + suggestion
            }
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            details += " Underlying: " + underlying.domain + ":" + String(underlying.code)
        }
        if let nested = ns.userInfo["NSMultipleUnderlyingErrorsKey"] as? [NSError] {
            details += nested.prefix(3).map {
                " Underlying: " + $0.domain + ":" + String($0.code)
            }.joined()
        }
        return String(details.prefix(600))
    }

    // Not an AI replacement: encyclopedic lookup for general factual questions.
    // Runs only when the user enables online fallback in Settings.
    private static func wikipediaAnswer(for question: String) async throws -> String {
        let clean = question.replacingOccurrences(
            of: #"(?i)^\s*(who\s+(is|was|are|were)|what\s+(is|was|are|were)|tell\s+me\s+about|explain)\s+"#,
            with:"", options:.regularExpression
        ).trimmingCharacters(in:.whitespacesAndNewlines)
        guard clean.count >= 2 && clean.count <= 150 else {
            throw NSError(domain:"SolosJarvis.Wikipedia",code:1,userInfo:[
                NSLocalizedDescriptionKey:"Wikipedia fallback only handles short factual queries."
            ])
        }
        var search = URLComponents(string:"https://en.wikipedia.org/w/rest.php/v1/search/page")!
        search.queryItems = [
            URLQueryItem(name:"q",value:clean),
            URLQueryItem(name:"limit",value:"1")
        ]
        guard let searchURL = search.url else {
            throw URLError(.badURL)
        }
        var searchRequest = URLRequest(url:searchURL)
        searchRequest.setValue("SolosJarvis/17.0 (iOS personal education assistant)",
                               forHTTPHeaderField:"User-Agent")
        searchRequest.timeoutInterval = 12
        let (searchData, searchResponse) = try await URLSession.shared.data(for:searchRequest)
        guard (searchResponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        struct WikiSearch: Decodable {
            struct Page: Decodable { let key: String; let title: String }
            let pages: [Page]
        }
        let results = try JSONDecoder().decode(WikiSearch.self,from:searchData)
        guard let first = results.pages.first else {
            throw NSError(domain:"SolosJarvis.Wikipedia",code:404,userInfo:[
                NSLocalizedDescriptionKey:"No matching Wikipedia article was found."
            ])
        }
        var summaryURL = URLComponents()
        summaryURL.scheme = "https"
        summaryURL.host = "en.wikipedia.org"
        summaryURL.path = "/api/rest_v1/page/summary/" + first.key
        guard let endpoint = summaryURL.url else { throw URLError(.badURL) }
        var request = URLRequest(url:endpoint)
        request.setValue("SolosJarvis/17.0 (iOS personal education assistant)",
                         forHTTPHeaderField:"User-Agent")
        request.timeoutInterval = 12
        let (data, http) = try await URLSession.shared.data(for:request)
        guard (http as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        struct WikiSummary: Decodable {
            let title: String?
            let extract: String?
        }
        let summary = try JSONDecoder().decode(WikiSummary.self,from:data)
        guard let extract = summary.extract?.trimmingCharacters(in:.whitespacesAndNewlines),
              !extract.isEmpty else {
            throw NSError(domain:"SolosJarvis.Wikipedia",code:3,userInfo:[
                NSLocalizedDescriptionKey:"Wikipedia did not provide a readable summary."
            ])
        }
        // Label sources clearly on both the glasses and spoken playback.
        return "According to Wikipedia: " + String(extract.prefix(540))
    }

    private func scheduleWakeRearm(after delay:TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline:.now()+delay) { [weak self] in
            guard let self, self.continuousWakeWanted, !self.listening else { return }
            // An AI task or an earlier authorization callback may still be
            // settling. The periodic watchdog also checks for recovery.
            guard !self.asking else { return }
            self.startListening()
        }
    }

    private func resumeWakeIfNeeded() {
        guard !musicPlaybackActive || UserDefaults.standard.bool(forKey:"jarvisListenWhileMusic") else {
            return
        }
        guard continuousWakeWanted, !listening, !startingRecognition, !asking,
              !awaitingSpeechCompletion, !accessory.isSpeaking else { return }
        startListening()
    }

    func setMusicPlaybackActive(_ active:Bool) {
        musicPlaybackActive = active
        if active && !UserDefaults.standard.bool(forKey:"jarvisListenWhileMusic") {
            stopListening()
            voiceStatus = "Music playback protected — microphone paused to prevent Apple Music interruption"
        } else if !active && UserDefaults.standard.bool(forKey:"jarvisLockScreenWake") {
            resumeWakeIfNeeded()
        }
    }

    func setHUDCaptionsActive(_ active: Bool) {
        hudCaptionsActive = active
        if active {
            stopListening()
            voiceStatus = "Microphone handed to live captions/translation HUD"
        } else if UserDefaults.standard.bool(forKey:"jarvisLockScreenWake") {
            startListening()
        }
    }

    func resumeAfterScreenUnlock() {
        guard !hudCaptionsActive else { return }
        guard !musicPlaybackActive || UserDefaults.standard.bool(forKey:"jarvisListenWhileMusic") else {
            voiceStatus = "Music playing — Jarvis microphone remains paused"
            return
        }
        if UserDefaults.standard.bool(forKey:"jarvisLockScreenWake") {
            continuousWakeWanted = true
            if !listening || !audioEngine.isRunning {
                restartRecognitionSoon()
            }
        }
    }

    func startListening() {
        guard !musicPlaybackActive || UserDefaults.standard.bool(forKey:"jarvisListenWhileMusic") else {
            voiceStatus = "Music playing — toggle simultaneous listening in settings if needed"
            return
        }
        guard !hudCaptionsActive else {
            voiceStatus = "Live captions currently own the microphone"
            return
        }
        // Guard asynchronous permission callbacks to prevent two overlapping
        // audio-engine taps or stale callbacks restarting after STOP.
        continuousWakeWanted = true
        guard !awaitingSpeechCompletion, !accessory.isSpeaking else { return }
        guard !listening, !startingRecognition else { return }
        startingRecognition = true
        let expectedGeneration = recognitionGeneration
        SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.continuousWakeWanted,
                      self.recognitionGeneration == expectedGeneration else {
                    self.startingRecognition = false
                    return
                }
                guard authorization == .authorized else {
                    self.startingRecognition = false
                    self.voiceStatus = "Speech recognition permission denied"
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        guard self.continuousWakeWanted,
                              self.recognitionGeneration == expectedGeneration else {
                            self.startingRecognition = false
                            return
                        }
                        self.startingRecognition = false
                        if granted { self.beginRecording() }
                        else { self.voiceStatus = "Microphone permission denied" }
                    }
                }
            }
        }
    }
    private func beginRecording() {
        guard !listening else { return }
        recognitionGeneration += 1
        let generation = recognitionGeneration
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            voiceStatus = "iOS speech recognition is unavailable. Check Speech Recognition in Settings."
            return
        }
        let allowOnline = UserDefaults.standard.bool(forKey:"jarvisAllowOnlineSpeech")
        guard speechRecognizer.supportsOnDeviceRecognition || allowOnline else {
            voiceStatus = "Offline English recognition is unavailable. Enable online speech in Jarvis Settings or install an offline language pack."
            return
        }
        if awaitingFollowUp && Date() >= followUpExpiresAt { awaitingFollowUp = false }
        heardWake = false
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        recognitionRequest?.requiresOnDeviceRecognition = !allowOnline
        guard let request = recognitionRequest else { return }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode:.default,
                                       options:[.mixWithOthers,.allowBluetoothHFP,.defaultToSpeaker])
            try audio.setActive(true, options:.notifyOthersOnDeactivation)
            // Works with any paired HFP headset, even without Solos HUD.
            // iOS selects the playback route; it does not offer independent
            // output devices for music and Jarvis inside one audio session.
            let preference = UserDefaults.standard.string(forKey:"jarvisMicrophoneSource") ?? "bluetooth"
            let inputs = audio.availableInputs ?? []
            let selected: AVAudioSessionPortDescription?
            if preference == "iphone" {
                selected = inputs.first(where:{$0.portType == .builtInMic})
            } else if preference == "solos" {
                selected = inputs.first(where:{
                    $0.portType == .bluetoothHFP &&
                    ($0.portName.localizedCaseInsensitiveContains("Solos") ||
                     $0.uid.localizedCaseInsensitiveContains("Solos"))
                })
            } else {
                selected = inputs.first(where:{$0.portType == .bluetoothHFP})
            }
            // Bluetooth is preferred, not mandatory. On an unpaired iPhone,
            // silently refusing to listen made "Hey Jarvis" appear broken.
            let chosen = selected ?? (preference == "solos" ? nil : inputs.first(where:{
                $0.portType == .builtInMic
            }))
            guard let chosen else {
                voiceStatus = "Selected microphone unavailable. Pair a Bluetooth headset with microphone or select iPhone mic."
                startingRecognition = false
                return
            }
            try audio.setPreferredInput(chosen)
            let node = audioEngine.inputNode
            let format = node.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                voiceStatus = "iOS microphone route isn't ready. Reconnect headset or choose the iPhone microphone."
                stopListening()
                return
            }
            if wakeAudioTapInstalled {
                node.removeTap(onBus:0)
                wakeAudioTapInstalled = false
            }
            // Tap survives speech-task rotation; changing recognizers must NOT
            // stop AVAudioEngine or reactivate the system audio session.
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self else { return }
                self.recognitionRequestLock.lock()
                self.recognitionRequest?.append(buffer)
                self.recognitionRequestLock.unlock()
                // Meter the existing mic tap; do not install a second tap or
                // reconfigure the Bluetooth audio route just for visuals.
                guard let channel = buffer.floatChannelData?[0] else { return }
                let frames = Int(buffer.frameLength)
                guard frames > 0 else { return }
                var power: Float = 0
                let strideSize = max(1, frames / 128)
                var samples = 0
                for index in stride(from:0,to:frames,by:strideSize) {
                    power += channel[index] * channel[index]
                    samples += 1
                }
                let rms = sqrt(power / Float(max(1,samples)))
                let level = min(1.0, max(0.0, Double(rms) * 11.0))
                self.meterLock.lock()
                let now = Date()
                let publish = now.timeIntervalSince(self.lastMeterPublish) >= 0.08
                if publish { self.lastMeterPublish = now }
                self.meterLock.unlock()
                if publish {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.listening else { return }
                        self.microphoneLevel = self.microphoneLevel * 0.45 + level * 0.55
                        self.userVoiceActive = self.microphoneLevel >= 0.13
                    }
                }
            }
            wakeAudioTapInstalled = true
            audioEngine.prepare()
            try audioEngine.start()
            listening = true
            recognizerStartedAt = Date()
            voiceStatus = (awaitingFollowUp ? "Listening for your question • " :
                           "Listening for Hey Jarvis • ") + chosen.portName
            // Rotate only the speech recognizer, keeping the microphone stream
            // running and the audio route stable for Apple Music.
            scheduleWakeTaskRotation(generation:generation)
            startWakeTask(request,recognizer:speechRecognizer,generation:generation)
        } catch {
            voiceStatus = "Microphone could not start: \(error.localizedDescription)"
            stopListening()
        }
    }
    private func scheduleWakeTaskRotation(generation:Int) {
        DispatchQueue.main.asyncAfter(deadline:.now() + 48) { [weak self] in
            guard let self, self.recognitionGeneration == generation,
                  self.listening, !self.heardWake else { return }
            self.rotateWakeRecognitionTask()
        }
    }

    private func rotateWakeRecognitionTask() {
        guard listening, continuousWakeWanted, !hudCaptionsActive,
              audioEngine.isRunning, !heardWake else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }
        recognitionGeneration += 1
        let generation = recognitionGeneration
        speechTask?.cancel()
        speechTask = nil
        recognitionRequestLock.lock()
        recognitionRequest?.endAudio()
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        recognitionRequest?.requiresOnDeviceRecognition = !UserDefaults.standard.bool(forKey:"jarvisAllowOnlineSpeech")
        let newRequest = recognitionRequest
        recognitionRequestLock.unlock()
        guard let newRequest else { return }
        recognizerStartedAt = Date()
        voiceStatus = "Listening for Hey Jarvis (music uninterrupted)"
        startWakeTask(newRequest,recognizer:recognizer,generation:generation)
        scheduleWakeTaskRotation(generation:generation)
    }

    private func startWakeTask(_ request:SFSpeechAudioBufferRecognitionRequest,
                               recognizer:SFSpeechRecognizer,generation:Int) {
            speechTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self, self.recognitionGeneration == generation else { return }
                    if let result {
                        let heard = result.bestTranscription.formattedString
                        self.transcribed = heard
                        if let words = JarvisWakePhrase.question(afterWakeIn:heard) {
                            if !self.heardWake {
                                self.heardWake = true
                                self.pendingVoiceQuestion = ""
                                if self.accessory.isSpeaking {
                                    self.accessory.interruptSpeech()
                                    self.awaitingSpeechCompletion = false
                                }
                            }
                            if !words.isEmpty {
                                self.pendingVoiceQuestion = words
                                self.scheduleQuestionAfterSilence(generation:generation)
                            } else {
                                self.scheduleWakeAcknowledgement(generation:generation)
                            }
                        } else if self.heardWake {
                            // Some partial results omit the wake phrase after recognition
                            // corrects its transcript. Keep collecting until silence.
                            let words = heard.trimmingCharacters(in:.whitespacesAndNewlines)
                            if !words.isEmpty {
                                self.pendingVoiceQuestion = words
                                self.scheduleQuestionAfterSilence(generation:generation)
                            }
                        } else if self.awaitingFollowUp && Date() < self.followUpExpiresAt {
                            // After Jarvis says "I'm listening", the next phrase
                            // is a question; the person needn't repeat the wake word.
                            let words = heard.trimmingCharacters(in:.whitespacesAndNewlines)
                            if !words.isEmpty {
                                self.heardWake = true
                                self.pendingVoiceQuestion = words
                                self.scheduleQuestionAfterSilence(generation:generation)
                            }
                        }
                        if result.isFinal && self.listening {
                            if self.heardWake && !self.pendingVoiceQuestion.isEmpty {
                                self.submitPendingVoiceQuestion(generation:generation)
                            } else if self.heardWake {
                                self.acknowledgeWake(generation:generation)
                            } else {
                                self.rotateWakeRecognitionTask()
                            }
                        }
                    }
                    if let error, self.listening {
                        self.voiceStatus = "Speech task rotated after error: \(error.localizedDescription)"
                        self.rotateWakeRecognitionTask()
                    }
                }
            }

    }

    private func scheduleWakeAcknowledgement(generation:Int) {
        questionSilenceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.acknowledgeWake(generation:generation)
        }
        questionSilenceWork = work
        DispatchQueue.main.asyncAfter(deadline:.now()+0.85,execute:work)
        voiceStatus = "Hey Jarvis heard — waiting for your question"
    }

    private func acknowledgeWake(generation:Int) {
        guard recognitionGeneration == generation, heardWake,
              pendingVoiceQuestion.isEmpty else { return }
        questionSilenceWork?.cancel()
        questionSilenceWork = nil
        let shouldResume = continuousWakeWanted
        stopListening()
        continuousWakeWanted = shouldResume
        guard shouldResume else { return }
        awaitingFollowUp = true
        followUpExpiresAt = Date().addingTimeInterval(12)
        let expiry = followUpExpiresAt
        DispatchQueue.main.asyncAfter(deadline:.now()+12) { [weak self] in
            guard let self, self.awaitingFollowUp,
                  self.followUpExpiresAt == expiry else { return }
            self.awaitingFollowUp = false
            if self.listening { self.voiceStatus = "Listening for Hey Jarvis" }
        }
        if UserDefaults.standard.object(forKey:"jarvisSpeakAnswers") as? Bool ?? true {
            awaitingSpeechCompletion = true
            speechStartedAt = Date()
            voiceStatus = "Jarvis answering wake phrase — microphone paused"
            accessory.speak("Yes, I'm listening.")
        } else {
            voiceStatus = "Wake detected — listening for your question"
            scheduleWakeRearm(after:0.2)
        }
    }

    // Do not decide a question is complete by character count. Every new
    // transcription cancels the previous silence timer. A natural pause of
    // 0.75 seconds (or Apple's final recognition result) submits the question.
    private func scheduleQuestionAfterSilence(generation:Int) {
        questionSilenceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.recognitionGeneration == generation else { return }
            self.submitPendingVoiceQuestion(generation:generation)
        }
        questionSilenceWork = work
        DispatchQueue.main.asyncAfter(deadline:.now()+0.75,execute:work)
        voiceStatus = "Listening to your full question — pause when done"
    }

    private func submitPendingVoiceQuestion(generation:Int) {
        guard recognitionGeneration == generation else { return }
        let question = pendingVoiceQuestion.trimmingCharacters(
            in:.whitespacesAndNewlines.union(.punctuationCharacters))
        guard !question.isEmpty else { return }
        questionSilenceWork?.cancel()
        questionSilenceWork = nil
        pendingVoiceQuestion = ""
        awaitingFollowUp = false
        let rearm = continuousWakeWanted
        stopListening()
        continuousWakeWanted = rearm
        // Mode requests are processed locally without waking an AI model.
        // The HUD controller stops/restarts the correct microphone owner.
        if onHUDVoiceCommand?(question) == true {
            voiceStatus = "Jarvis switched the HUD"
            if rearm && !hudCaptionsActive { scheduleWakeRearm(after:0.3) }
            return
        }
        if !asking { ask(question) }
        else { voiceStatus = "Finishing previous answer; say Hey Jarvis again" }
    }

    private func restartRecognitionSoon() {
        guard !awaitingSpeechCompletion, !accessory.isSpeaking, !asking else { return }
        // Audio route + engine notifications can arrive in a burst. Coalesce
        // them so restarts cannot cancel each other indefinitely.
        guard !restartScheduled else { return }
        let rearm = continuousWakeWanted
        stopListening()
        continuousWakeWanted = rearm
        restartScheduled = true
        DispatchQueue.main.asyncAfter(deadline:.now()+0.4) { [weak self] in
            guard let self else { return }
            self.restartScheduled = false
            guard self.continuousWakeWanted, !self.listening else { return }
            self.startListening()
        }
    }

    deinit {
        lockWatchdog?.invalidate()
        for observer in audioObservers { NotificationCenter.default.removeObserver(observer) }
    }

    func stopListening() {
        continuousWakeWanted = false
        startingRecognition = false
        awaitingSpeechCompletion = false
        questionSilenceWork?.cancel()
        questionSilenceWork = nil
        pendingVoiceQuestion = ""
        awaitingFollowUp = false
        followUpExpiresAt = .distantPast
        recognitionGeneration += 1
        if audioEngine.isRunning { audioEngine.stop() }
        if wakeAudioTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            wakeAudioTapInstalled = false
        }
        recognitionRequestLock.lock()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionRequestLock.unlock()
        speechTask?.cancel()
        speechTask = nil
        listening = false
        microphoneLevel = 0
        userVoiceActive = false
        voiceStatus = "Not listening"
    }
}
