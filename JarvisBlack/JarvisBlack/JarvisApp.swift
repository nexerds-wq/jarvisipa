import SwiftUI

@main
struct JarvisApp: App {
    @StateObject private var assistant = JarvisController()

    var body: some Scene {
        WindowGroup {
            Color.black
                .ignoresSafeArea()
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
                .task { await assistant.launch() }
        }
    }
}
