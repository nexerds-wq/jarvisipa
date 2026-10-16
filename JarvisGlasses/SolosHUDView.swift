import SwiftUI

/// A conservative direct-iPhone attempt: Bluetooth audio + MFi accessory discovery.
/// Does not pretend CoreBluetooth can talk to the Solos RFCOMM display.
struct SolosHUDView: View {
    @StateObject private var classic = SolosClassicManager()
    @State private var message = "Hello. Jarvis is ready."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Jarvis HUD preview · 428 × 240") {
                    Image(uiImage: SolosDisplayPacket.render(message: message))
                        .resizable()
                        .aspectRatio(CGFloat(SolosDisplayPacket.width) / CGFloat(SolosDisplayPacket.height), contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.vertical, 6)
                }

                GroupBox("Message for Solos") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Jarvis message", text: $message, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Speak via Bluetooth") { classic.speak(message) }
                                .buttonStyle(.borderedProminent)
                            Button("Send to HUD") { classic.sendHUD(message) }
                                .buttonStyle(.bordered)
                        }
                        Text("Audio uses your iPhone's current output device. The HUD requires an authorized accessory data connection.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Direct Bluetooth diagnostic") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Audio route")
                            Spacer()
                            Text(classic.audioRoute)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                        Text(classic.status)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Refresh paired accessories") { classic.refresh() }
                            .buttonStyle(.bordered)
                        if classic.accessories.isEmpty {
                            Text("No MFi-approved accessories visible. Normal Bluetooth pairing by itself does not unlock Classic RFCOMM data on iOS.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(classic.accessories) { accessory in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(accessory.name).font(.headline)
                                Text("Manufacturer: \(accessory.manufacturer)")
                                    .font(.caption)
                                if accessory.protocols.isEmpty {
                                    Text("No accessory data protocols advertised.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(accessory.protocols, id: \.self) { proto in
                                    Text(proto)
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                    if classic.declaredProtocols.contains(proto) {
                                        Button("Connect \(proto)") {
                                            classic.connect(accessoryID: accessory.id, protocolString: proto)
                                        }
                                        .buttonStyle(.bordered)
                                    } else {
                                        Button("Test protocol / show next step") {
                                            classic.connect(accessoryID: accessory.id, protocolString: proto)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                            Divider()
                        }
                        if !classic.connectedName.isEmpty {
                            Button("Disconnect display") { classic.disconnect() }
                                .buttonStyle(.bordered)
                        }
                    }
                }

                GroupBox("Why this is limited") {
                    Text("Solos 2018 sends pictures over Bluetooth Classic RFCOMM. Apple's public CoreBluetooth API cannot open those sockets. iOS can use Classic data only for manufacturer-approved MFi protocols through ExternalAccessory. This screen tests for one without jailbreaking or pretending BLE is the display connection. If no data protocol is exposed, Bluetooth audio can still work but the display cannot be driven directly.")
                        .font(.subheadline)
                }
            }
            .padding()
        }
        .navigationTitle("Solos + Jarvis")
        .onAppear { classic.refresh() }
    }
}
