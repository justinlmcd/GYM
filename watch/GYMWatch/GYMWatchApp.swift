import SwiftUI

@main
struct GYMWatchApp: App {
    @State private var store = Store()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if store.signedIn {
                    HomeView()
                } else {
                    SignInView()
                }
            }
            .environment(store)
            .task { await store.start() }
            .onChange(of: scenePhase) { _, phase in
                // Upload anything logged offline, and refresh today's numbers, whenever the app comes back.
                if phase == .active { Task { await store.flush(); await store.loadHub() } }
            }
        }
        // Half an hour before the evening reminder, refresh today's numbers so its text is current.
        .backgroundTask(.appRefresh(Store.refreshTaskID)) { [store] in
            await store.backgroundRefresh()
        }
    }
}
