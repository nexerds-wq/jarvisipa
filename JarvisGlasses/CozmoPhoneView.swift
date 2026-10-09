import SwiftUI
import CoreBluetooth

// This advertises a BLE service for a future external direction-finding receiver.
// Cozmo's built-in hardware cannot read or locate this beacon by itself.
final class PhoneBeacon: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    static let serviceID = CBUUID(string: "9A2D1E90-4F52-4C49-9C10-5E2C9B4DAB01")
    @Published var status = "Not started"
    @Published var enabled = false
    private var manager: CBPeripheralManager?

    func start() {
        enabled = true
        if manager == nil {
            manager = CBPeripheralManager(delegate: self, queue: nil)
        } else {
            updateAdvertising()
        }
    }

    func stop() {
        enabled = false
        manager?.stopAdvertising()
        status = "Stopped"
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        updateAdvertising()
    }

    private func updateAdvertising() {
        guard let manager else { return }
        guard enabled else { manager.stopAdvertising(); return }
        guard manager.state == .poweredOn else {
            status = "Bluetooth unavailable or permission needed"
            return
        }
        manager.stopAdvertising()
        manager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceID]
        ])
        status = "Advertising phone beacon (not Cozmo-connected)"
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error { status = "Beacon error: \(error.localizedDescription)" }
    }
}

struct CozmoPhoneView: View {
    @StateObject private var beacon = PhoneBeacon()

    var body: some View {
        Form {
            Section("Phone beacon") {
                Text(beacon.status)
                Button(beacon.enabled ? "Stop beacon" : "Start beacon") {
                    beacon.enabled ? beacon.stop() : beacon.start()
                }
            }
            Section("Tracking status") {
                Label("Robot not connected", systemImage: "exclamationmark.triangle")
                Text("This IPA broadcasts a Bluetooth identifier. Cozmo cannot determine your phone's direction or follow it using its stock hardware. An external BLE direction-finding receiver and a Cozmo motor controller are required.")
                Text("The beacon may stop or change behavior when iOS suspends the app.")
            }
        }
        .navigationTitle("Cozmo Phone")
        .onDisappear { beacon.stop() }
    }
}
