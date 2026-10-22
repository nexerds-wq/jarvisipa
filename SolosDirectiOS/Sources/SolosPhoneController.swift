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
    @Published var voiceStatus = "Not listening"
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
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechTask: SFSpeechRecognitionTask?
    private var heardWake = false
    private var lastQuestion = ""
    private var continuousWakeWanted = false
    private var timer: Timer?
    private var lastPedometerDay = Calendar.current.startOfDay(for: Date())
    private var asking = false

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        central = CBCentralManager(delegate: self, queue: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
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
        steps = data.numberOfSteps.stringValue
        if let meters = data.distance?.doubleValue {
            distance = String(format: "%.2f mi", meters / 1609.344)
        } else {
            distance = "N/A"
        }
        motionStatus = "Steps are from today's iPhone motion history."
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
        coordinates = String(format: "GPS %.4f, %.4f", item.coordinate.latitude, item.coordinate.longitude)
        locationStatus = String(format: "GPS accuracy: ±%.0f m", max(0, item.horizontalAccuracy))
        speed = item.speed >= 0 ? String(format: "%.1f mph", item.speed * 2.236936) : "–"
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
                if self.continuousWakeWanted {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 35.0) { [weak self] in
                        guard let self, self.continuousWakeWanted, !self.listening else { return }
                        self.startListening()
                    }
                }
            }
            if #available(iOS 26.0, *) {
                guard SystemLanguageModel.default.isAvailable else {
                    self.aiStatus = "Apple Intelligence on-device model is unavailable. Enable Apple Intelligence and download its model in Settings."
                    self.aiAnswer = self.aiStatus
                    return
                }
                do {
                    let session = LanguageModelSession(instructions: "You are JARVIS, a helpful offline smart glasses assistant. Give brief, accurate spoken answers of one or two sentences. Do not claim access to internet or live information.")
                    let result = try await session.respond(to: trimmed)
                    self.aiAnswer = result.content
                    self.aiStatus = "Answered locally (no AI API key or computer)"
                    // The dedicated OLED lens renderer displays complete answer pages.
                    // Avoid a competing raw HUD packet that can overwrite them.
                    if UserDefaults.standard.object(forKey: "jarvisSpeakAnswers") as? Bool ?? true {
                        // Stop microphone capture before playback: the recognition session
                        // otherwise keeps the audio route in record mode on some iPhones.
                        let shouldResume = self.continuousWakeWanted
                        self.stopListening()
                        self.continuousWakeWanted = shouldResume
                        do {
                            let audio = AVAudioSession.sharedInstance()
                            try audio.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .allowBluetoothA2DP])
                            try audio.setActive(true, options: .notifyOthersOnDeactivation)
                            self.voiceStatus = "Speaking Jarvis answer through " + self.accessory.audioRoute
                        } catch {
                            self.voiceStatus = "Spoken audio route: \(error.localizedDescription)"
                        }
                        self.accessory.speak(result.content)
                    }
                } catch {
                    self.aiStatus = "On-device JARVIS error: \(error.localizedDescription)"
                    self.aiAnswer = self.aiStatus
                }
            }
        }
    }
    func startListening() {
        continuousWakeWanted = true
        SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
            DispatchQueue.main.async {
                guard let self else { return }
                guard authorization == .authorized else { self.voiceStatus = "Speech recognition permission denied"; return }
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        if granted { self.beginRecording() }
                        else { self.voiceStatus = "Microphone permission denied" }
                    }
                }
            }
        }
    }
    private func beginRecording() {
        guard !listening else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable, speechRecognizer.supportsOnDeviceRecognition else {
            voiceStatus = "This iPhone language pack does not support offline speech. Use typed questions."
            return
        }
        heardWake = false
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        recognitionRequest?.requiresOnDeviceRecognition = true
        guard let request = recognitionRequest else { return }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audio.setActive(true, options: .notifyOthersOnDeactivation)
            let node = audioEngine.inputNode
            let format = node.outputFormat(forBus: 0)
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            audioEngine.prepare()
            try audioEngine.start()
            listening = true
            voiceStatus = "Listening for Hey Jarvis (iPhone microphone)"
            speechTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let result {
                        let heard = result.bestTranscription.formattedString
                        self.transcribed = heard
                        if let range = heard.range(of: "hey jarvis", options: .caseInsensitive), !self.heardWake {
                            let question = String(heard[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                            if !question.isEmpty && (result.isFinal || question.count > 8) {
                                self.heardWake = true
                                self.stopListening()
                                self.continuousWakeWanted = true
                                self.ask(question)
                            } else { self.voiceStatus = "Hey Jarvis heard! Speak your question..." }
                        }
                        if result.isFinal && self.listening && !self.heardWake {
                            self.stopListening()
                            self.continuousWakeWanted = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                if self.continuousWakeWanted { self.startListening() }
                            }
                        }
                    }
                    if error != nil && self.listening { self.stopListening(); self.voiceStatus = "Voice stopped; tap Start to retry" }
                }
            }
        } catch {
            voiceStatus = "Microphone could not start: \(error.localizedDescription)"
            stopListening()
        }
    }
    func stopListening() {
        continuousWakeWanted = false
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        speechTask?.cancel()
        speechTask = nil
        recognitionRequest = nil
        listening = false
        voiceStatus = "Not listening"
    }
}
