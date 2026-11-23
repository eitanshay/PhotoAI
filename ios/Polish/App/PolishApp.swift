import SwiftUI
import SwiftData

@main
struct PolishApp: App {
    @State private var settings: SettingsStore
    @State private var session: EnhanceSession

    init() {
        let s = SettingsStore()
        _settings = State(initialValue: s)
        _session = State(initialValue: EnhanceSession(settings: s))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(session)
        }
        .modelContainer(for: LibraryItem.self)
    }
}
