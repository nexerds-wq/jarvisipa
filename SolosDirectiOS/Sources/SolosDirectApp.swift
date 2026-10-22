import SwiftUI

@main
struct SolosDirectApp: App {
    @StateObject private var phone = SolosPhoneController()
    var body: some Scene {
        WindowGroup {
            SolosDirectHome(phone: phone)
                .preferredColorScheme(.dark)
                .onAppear { phone.refreshSensors(); phone.accessory.refresh() }
        }
    }
}

struct SolosDirectHome: View {
    @ObservedObject var phone: SolosPhoneController
    @ObservedObject private var accessory: SolosClassicManager
    @StateObject private var handsFree = SolosHandsFreeEngine()
    init(phone: SolosPhoneController) {
        self.phone = phone
        self._accessory = ObservedObject(wrappedValue: phone.accessory)
    }
    @State private var question = "Hey Jarvis, what is a black hole?"
    @State private var customHUD = "HELLO FROM IPHONE"
    @AppStorage("solosOrientationMode") private var orientationMode = 0
    @AppStorage("solosAutoDashboard") private var autoDashboard = true
    @State private var lastDashboardMinute = ""
    @State private var page = 0
    @State private var lastOledMessage = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    handsFreeCard
                    SolosAccessoryCard(manager: phone.accessory)
                    VStack(alignment: .leading, spacing: 9) {
                        Text("IPHONE OFFLINE JARVIS").font(.headline).foregroundStyle(.mint)
                        Text(phone.aiStatus).font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $question)
                            .frame(minHeight: 90)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                        Button("ASK ON-DEVICE AI") { phone.ask(question) }
                            .buttonStyle(.borderedProminent).tint(.mint)
                        HStack {
                            Button(phone.listening ? "STOP LISTENING" : "START HEY JARVIS") {
                                phone.listening ? phone.stopListening() : phone.startListening()
                            }.buttonStyle(.bordered)
                            Image(systemName: "mic.fill").foregroundStyle(.mint)
                        }
                        Text(phone.voiceStatus).font(.caption).foregroundStyle(.secondary)
                        if !phone.transcribed.isEmpty {
                            Text("Heard: \(phone.transcribed)").font(.caption)
                        }
                        Text("JARVIS:").font(.caption.bold()).foregroundStyle(.mint)
                        Text(phone.aiAnswer)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    }.card()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("LIVE IPHONE DASHBOARD").font(.headline).foregroundStyle(.mint)
                        HStack(alignment: .firstTextBaseline) {
                            Text(phone.clock).font(.system(size: 37, weight: .bold, design: .rounded))
                            Spacer()
                            Text("OFFLINE").foregroundStyle(.mint).font(.caption.bold())
                        }
                        Text(phone.dateLine).foregroundStyle(.secondary)
                        HStack {
                            Label("\(phone.steps) steps", systemImage: "figure.walk")
                            Spacer()
                            Label(phone.distance, systemImage: "map")
                        }.font(.subheadline)
                        HStack {
                            Label(phone.battery, systemImage: "battery.100percent")
                            Spacer()
                            Label(phone.speed, systemImage: "location")
                        }.font(.subheadline)
                        Text(phone.coordinates).font(.caption).foregroundStyle(.mint)
                        Text(phone.motionStatus).font(.caption2).foregroundStyle(.secondary)
                        Text(phone.locationStatus).font(.caption2).foregroundStyle(.secondary)
                        Toggle("LIVE OLED DASHBOARD: refresh on lens each minute", isOn: $autoDashboard)
                            .tint(.mint)
                            .onChange(of: autoDashboard) { _, enabled in
                                if enabled { sendDashboard() }
                            }
                        HStack {
                            Button("SEND OLED DASHBOARD") { sendDashboard() }
                                .buttonStyle(.borderedProminent).tint(.mint)
                            Button("REFRESH SENSORS") { phone.refreshSensors() }
                                .buttonStyle(.bordered)
                        }
                        Text("GPS needs Location permission; daily steps and distance need Motion & Fitness permission. Live updates run while this app is open.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.card()
                    StableExtrasView(phone: phone)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TEST CUSTOM HUD — ORIGINAL V4 CONNECTION").font(.headline).foregroundStyle(.mint)
                        Text("Correct upside-down AND mirrored letters independently. Start with V4 Original, then try each correction.")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("Lens image orientation", selection: $orientationMode) {
                            Text("0 • V4 ORIGINAL").tag(0)
                            Text("1 • ROTATE 180°").tag(1)
                            Text("2 • MIRROR LEFT/RIGHT").tag(2)
                            Text("3 • FLIP TOP/BOTTOM").tag(3)
                        }
                        .pickerStyle(.menu)
                        .tint(.mint)
                        Button("SEND ORIENTATION TEST — ABC 123 →") {
                            phone.accessory.sendHUD("TOP ABC 123 >\nLEFT > RIGHT\nBOTTOM 789")
                        }
                        .buttonStyle(.borderedProminent).tint(.mint)
                        TextField("Text for Solos display", text: $customHUD, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        Button("SEND 428 × 240 RLE565 IMAGE") { phone.accessory.sendHUD(customHUD) }
                            .buttonStyle(.bordered)
                        if let image = SolosDisplayPacket.imagePacket(message: customHUD) {
                            Text("Encoded Solos frame: \(image.count) bytes").font(.caption).foregroundStyle(.secondary)
                        }
                        Image(uiImage: SolosDisplayPacket.render(message: customHUD))
                            .resizable().aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text("This preview appears on iPhone regardless of Bluetooth. It appears in your glasses only if an Apple-authorized display connection succeeds.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.card()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BLUETOOTH DIAGNOSTICS").font(.headline).foregroundStyle(.mint)
                        Text(phone.bleState).font(.caption).foregroundStyle(.secondary)
                        Button("SCAN BLUETOOTH LE") { phone.scanBLE() }.buttonStyle(.bordered)
                        ForEach(phone.discoveredBLE.prefix(15), id: \.self) { device in
                            Text(device).font(.caption.monospaced())
                        }
                        Text("Bluetooth LE scan does not expose the glasses' Bluetooth Classic RFCOMM channel. The official accessory protocol is still needed for direct HUD communication.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.card()
                }
                .padding()
            }
            .background(Color(red: 0.02, green: 0.055, blue: 0.075))
            .navigationTitle("SOLOS DIRECT")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { configureHandsFree() }
            .onChange(of: accessory.connectedProtocol) { _, proto in
                if !proto.isEmpty && autoDashboard {
                    sendModeHUD(handsFree.mode)
                }
            }
            .onChange(of: phone.aiAnswer) { _, text in
                if handsFree.mode == 3 && !text.isEmpty {
                    sendModeHUD(3, message: text)
                }
            }
            .onChange(of: phone.now) { _, time in
                guard autoDashboard, handsFree.mode == 0, !accessory.connectedProtocol.isEmpty else { return }
                let stamp = String(Calendar.current.component(.year, from: time)) + "-" +
                            String(Calendar.current.component(.month, from: time)) + "-" +
                            String(Calendar.current.component(.day, from: time)) + "-" +
                            String(Calendar.current.component(.hour, from: time)) + ":" +
                            String(Calendar.current.component(.minute, from: time))
                if stamp != lastDashboardMinute {
                    lastDashboardMinute = stamp
                    sendModeHUD(0)
                }
            }
        }
    }
    private func sendDashboard() {
        phone.refreshSensors()
        lastDashboardMinute = String(Calendar.current.component(.year, from: Date())) + "-" +
                              String(Calendar.current.component(.month, from: Date())) + "-" +
                              String(Calendar.current.component(.day, from: Date())) + "-" +
                              String(Calendar.current.component(.hour, from: Date())) + ":" +
                              String(Calendar.current.component(.minute, from: Date()))
        sendModeHUD(0)
    }
    private func configureHandsFree() {
        handsFree.enableMediaButtons()
        accessory.onAccessoryPacket = { packet in
            handsFree.input(packet)
        }
        handsFree.onModeChange = { selected in
            if selected == 0 { phone.refreshSensors() }
            NotificationCenter.default.post(name: Notification.Name("SolosHandsFreeMode"), object: nil, userInfo: ["mode":selected])
            sendModeHUD(selected)
        }
        if autoDashboard && !accessory.connectedProtocol.isEmpty {
            sendModeHUD(handsFree.mode)
        }
    }
    private func sendModeHUD(_ mode: Int, message: String = "") {
        guard !accessory.connectedProtocol.isEmpty else { return }
        let view = SolosProHUD.image(mode: mode,
            clock: phone.clock, date: phone.dateLine,
            steps: Int(phone.steps) ?? 0, distance: phone.distance,
            speed: phone.speed, battery: phone.battery,
            gps: phone.coordinates, message: message,
            detail: "SOLOS • \(mode + 1)/5 • HANDS FREE")
        accessory.sendHUDImage(view)
        lastOledMessage = message
    }
    private var handsFreeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("JARVIS / OLED CONTROL")
                    .font(.system(size: 19, weight: .black, design: .monospaced))
                    .foregroundStyle(.mint)
                Spacer()
                Circle().fill(accessory.connectedProtocol.isEmpty ? Color.orange : Color.mint)
                    .frame(width: 11, height: 11)
            }
            let modes = ["DASHBOARD", "CAPTIONS", "TRANSLATE", "JARVIS AI", "SETTINGS"]
            Text("MODE \(handsFree.mode + 1) / 5  •  \(modes[handsFree.mode])")
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
            Image(uiImage: SolosProHUD.image(
                mode: handsFree.mode, clock: phone.clock,
                date: phone.dateLine, steps: Int(phone.steps) ?? 0,
                distance: phone.distance, speed: phone.speed,
                battery: phone.battery, gps: phone.coordinates,
                message: lastOledMessage))
                .resizable()
                .interpolation(.none)
                .aspectRatio(428.0 / 240.0, contentMode:.fit)
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius:11).stroke(.mint.opacity(0.5), lineWidth:1))
            Text(handsFree.status).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("NEXT MODE") { handsFree.nextMode() }
                    .buttonStyle(.borderedProminent).tint(.mint)
                Button(handsFree.learning ? "PRESS GLASSES BUTTON..." : "LEARN GLASSES BUTTON") {
                    handsFree.learn()
                }.buttonStyle(.bordered)
            }
            Text("Accessory input: " + accessory.incomingSample)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.mint.opacity(0.8))
                .textSelection(.enabled)
            Text("Learned packet: " + handsFree.learnedDescription)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                Text("Standard play / next / previous headset controls can also switch modes when iOS delivers them.")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("RESET LEARNED") { handsFree.clearLearnedButton() }
                    .font(.caption2.bold()).foregroundStyle(.orange)
            }
            Text("Buttons that iOS exposes only as volume cannot be captured by a regular IPA. Keep this screen open during button learning.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(red:0.035,green:0.08,blue:0.10),in:RoundedRectangle(cornerRadius:18))
        .overlay(RoundedRectangle(cornerRadius:18).stroke(.mint.opacity(0.35),lineWidth:1))
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SOLOS  /  iPHONE")
                .font(.system(.title2, design: .monospaced).bold())
                .foregroundStyle(.mint)
            Text("One phone. On-device JARVIS. Direct display test.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }
}

struct SolosAccessoryCard: View {
    @ObservedObject var manager: SolosClassicManager
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("DIRECT GLASSES CONNECTION")
                .font(.headline).foregroundStyle(.mint)
            Text(manager.status).font(.caption)
            HStack {
                Button("PAIR / FIND ACCESSORY") { manager.openPicker() }.buttonStyle(.bordered)
                Button("REFRESH") { manager.refresh() }.buttonStyle(.bordered)
            }
            if manager.accessories.isEmpty {
                Text("No Apple External Accessory detected. If glasses connect only by RFCOMM, stock iOS cannot use that display channel.")
                    .font(.caption).foregroundStyle(.orange)
            }
            ForEach(manager.accessories) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name).font(.subheadline.bold())
                    Text("Maker: \(item.manufacturer)").font(.caption)
                    Text("Protocols: " + (item.protocols.isEmpty ? "none" : item.protocols.joined(separator: ", ")))
                        .font(.caption.monospaced()).textSelection(.enabled)
                    ForEach(item.protocols, id: \.self) { proto in
                        Button("CONNECT: \(proto)") {
                            manager.connect(accessoryID: item.id, protocolString: proto)
                        }
                        .buttonStyle(.borderedProminent).tint(.mint)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            }
            Text("Declared experimental protocols: \(manager.declaredProtocols.joined(separator: ", ")). Matching values alone do not bypass manufacturer authorization.")
                .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
        }.card()
    }
}

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.065, green: 0.12, blue: 0.15), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.mint.opacity(0.15), lineWidth: 1))
    }
}
extension View {
    fileprivate func card() -> some View { modifier(CardModifier()) }
}
