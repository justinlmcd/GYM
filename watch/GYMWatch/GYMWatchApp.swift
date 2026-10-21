import SwiftUI

@main
struct GYMWatchApp: App {
    @State private var store = Store()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if store.signedIn {
                    ExerciseListView()
                } else {
                    SignInView()
                }
            }
            .environment(store)
            .task { await store.start() }
            .onChange(of: scenePhase) { _, phase in
                // Upload anything logged offline whenever the app comes back.
                if phase == .active { Task { await store.flush() } }
            }
        }
    }
}
