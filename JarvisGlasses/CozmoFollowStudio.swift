import SwiftUI

struct CozmoFollowSettings: Codable {
    var target = "Shoes"
    var colors = ["Black", "White"]
    var combineColors = true
    var speed = 25.0
    var stopDistance = 35.0
    var sensitivity = 50.0
    var server = "http://192.168.1.100:8765"
    var token = ""
}
struct CozmoFollowStudio: View {
    @State private var settings = CozmoFollowSettings()
    @State private var message = "Not connected"
    @State private var running = false
    @State private var busy = false
    private let targets = ["Shoes", "Feet", "Legs", "Knees", "Hands", "Arms", "Torso", "Face", "Whole body"]
    private let colors = ["Black", "White", "Gray", "Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Pink", "Brown"]
    var body: some View {
        Form {
            Section("Follow target") {
                Picker("Body part", selection: $settings.target) {
                    ForEach(targets, id: \.self) { Text($0) }
                }
                Text("Body-part recognition needs a computer-side vision model. Color tracking is experimental.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Color matching") {
                Toggle("Combine selected colors", isOn: $settings.combineColors)
                ForEach(colors, id: \.self) { color in
                    Toggle(color, isOn: Binding(
                        get: { settings.colors.contains(color) },
                        set: { enabled in
                            if enabled && !settings.colors.contains(color) { settings.colors.append(color) }
                            if !enabled { settings.colors.removeAll { $0 == color } }
                        }))
                }
                Text("For multicolor shoes, select every shoe color. Matching dark shoes against dark floors may be unreliable.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Movement") {
                VStack(alignment: .leading) {
                    Text("Speed: \(Int(settings.speed)) mm/s")
                    Slider(value: $settings.speed, in: 10...50, step: 5)
                    Text("Stop distance: \(Int(settings.stopDistance)) cm")
                    Slider(value: $settings.stopDistance, in: 20...80, step: 5)
                    Text("Color sensitivity: \(Int(settings.sensitivity))%")
                    Slider(value: $settings.sensitivity, in: 10...100, step: 5)
                }
            }
            Section("Connection") {
                TextField("PC bridge address", text: $settings.server)
                    .textInputAutocapitalization(.never).keyboardType(.URL)
                    .autocorrectionDisabled()
                SecureField("Bridge access token", text: $settings.token)
                Text(message).font(.caption)
                Button("Save settings") { save(); message = "Saved on iPhone" }
                Button("Send settings to PC") { send("configure") }
                    .disabled(busy)
                Button("Start following") { send("start") }
                    .disabled(busy || running)
                    .buttonStyle(.borderedProminent)
                Button("STOP COZMO") { send("stop") }
                    .foregroundStyle(.red)
                    .disabled(busy)
            }
            Section("Safety") {
                Text("Requires a reachable Cozmo SDK bridge on your PC. This iPhone app cannot control Cozmo directly. Keep Cozmo on a clear flat floor away from stairs. STOP is a network command; if the network fails, stop the robot physically.")
                    .font(.caption)
            }
        }
        .navigationTitle("Cozmo Follow Studio")
        .onAppear(perform: load)
    }
    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "cozmo.follow.settings")
        }
    }
    private func load() {
        if let data = UserDefaults.standard.data(forKey: "cozmo.follow.settings"),
           let decoded = try? JSONDecoder().decode(CozmoFollowSettings.self, from: data) {
            settings = decoded
        }
    }
    private func send(_ command: String) {
        save()
        guard let base = URL(string: settings.server),
              let url = URL(string: "/command", relativeTo: base)?.absoluteURL,
              ["http", "https"].contains(url.scheme ?? "") else {
            message = "Enter a valid PC address"; return
        }
        busy = true
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(settings.token, forHTTPHeaderField: "X-Cozmo-Token")
        let payload = Command(command: command, settings: settings)
        request.httpBody = try? JSONEncoder().encode(payload)
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                busy = false
                if let error { message = "Connection failed: \(error.localizedDescription)"; return }
                guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
                    message = "PC bridge rejected command"; return
                }
                if command == "start" { running = true }
                if command == "stop" { running = false }
                message = "Sent \(command) to PC"
            }
        }.resume()
    }
    private struct Command: Encodable {
        let command: String
        let settings: CozmoFollowSettings
    }
}
