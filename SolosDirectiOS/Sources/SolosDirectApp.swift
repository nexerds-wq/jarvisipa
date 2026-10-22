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
    @State private var question = "Hey Jarvis, what is a black hole?"
    @State private var customHUD = "HELLO FROM IPHONE"
    @AppStorage("solosFlip180") private var flip180 = false
    @State private var page = 0
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
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
                            Label(phone.speed, systemImage: "location")
                        }.font(.subheadline)
                        Text(phone.coordinates).font(.caption).foregroundStyle(.secondary)
                        Button("DISPLAY DASHBOARD ON SOLOS") { phone.accessory.sendHUD(phone.dashboard) }
                            .buttonStyle(.bordered)
                    }.card()
                    SolosAccessoryCard(manager: phone.accessory)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TEST CUSTOM HUD — ORIGINAL V4 CONNECTION").font(.headline).foregroundStyle(.mint)
                        Toggle("ROTATE GLASSES DISPLAY 180°", isOn: $flip180)
                            .tint(.mint)
                        Text(flip180
                            ? "Correction ON: inverted image. Connection and packet headers unchanged."
                            : "Correction OFF: identical original V4 display encoding.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
        }
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
