import SwiftUI

@main
struct AURAStandaloneApp: App {
    @StateObject private var voice = AuraVoiceController()

    var body: some Scene {
        WindowGroup {
            AuraContentView()
                .environmentObject(voice)
                .preferredColorScheme(.dark)
        }
    }
}
