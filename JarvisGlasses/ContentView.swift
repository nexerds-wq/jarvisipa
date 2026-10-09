import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bluetooth: BLEController
    @EnvironmentObject var wakeWord: WakeWordManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    NavigationLink("Cozmo Phone Beacon") { CozmoPhoneView() }
                    connectionCard
                    wakeWordCard
                    devicesCard
                    notesCard
                }
                .padding()
            }
            .navigationTitle("Jarvis")
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: wakeWord.isListening ? "waveform.circle.fill" : "waveform.circle")
                .font(.system(size: 76))
                .symbolEffect(.pulse, isActive: wakeWord.isListening)

            Text("Jarvis Glasses")
                .font(.largeTitle.bold())

            Text("Say “Hey Jarvis” → wake M02S")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Glasses", systemImage: "eyeglasses")
                .font(.headline)

            infoRow("Selected", bluetooth.selectedName)
            infoRow("Connection", bluetooth.isConnected ? "Connected" : "Not connected")
            infoRow("Last wake", bluetooth.lastWakeText)

            Text(bluetooth.status)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Toggle("Auto reconnect", isOn: Binding(
                get: { bluetooth.autoReconnect },
                set: { bluetooth.setAutoReconnect($0) }
            ))

            HStack {
                Button(bluetooth.isScanning ? "Stop Scan" : "Scan") {
                    bluetooth.isScanning ? bluetooth.stopScan() : bluetooth.startScan()
                }
                .buttonStyle(.borderedProminent)

                Button("Test Jarvis") {
                    bluetooth.testWake()
                }
                .buttonStyle(.bordered)
            }
        }
        .cardStyle()
    }

    private var wakeWordCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Background Wake Word", systemImage: "mic.badge.plus")
                .font(.headline)

            Toggle("Listen for Hey Jarvis", isOn: Binding(
                get: { wakeWord.enabled },
                set: { wakeWord.setEnabled($0) }
            ))

            infoRow("Listener", wakeWord.isListening ? "Listening" : "Stopped")
            infoRow("Microphone", wakeWord.inputRoute)
            infoRow("Last detected", wakeWord.lastDetected)

            Text(wakeWord.status)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !wakeWord.liveText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live speech")
                        .font(.caption.bold())
                    Text(wakeWord.liveText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .cardStyle()
    }

    private var devicesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bluetooth devices")
                .font(.headline)

            if bluetooth.devices.isEmpty {
                Text("Tap Scan. Your M02S should move near the top of the list.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(bluetooth.devices.prefix(12)) { device in
                    Button {
                        bluetooth.select(device)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(device.id.uuidString)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text("\(device.rssi)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                    }
                    Divider()
                }
            }
        }
        .cardStyle()
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Locked/background mode", systemImage: "lock.iphone")
                .font(.headline)
            Text("Turn on Listen for Hey Jarvis while the app is open first. The app keeps an audio session and BLE background connection active when you leave the app or lock the phone.")
            Text("Do not swipe-force-close Jarvis Glasses. iOS stops background work after a force close. If iOS ever suspends speech recognition, reopen the app and it will restart.")
            Text("The app prefers the glasses Bluetooth HFP microphone when iOS exposes it. Otherwise it uses the iPhone microphone.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .cardStyle()
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .font(.subheadline)
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
