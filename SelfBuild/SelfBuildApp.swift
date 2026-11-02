import SwiftUI

@main
struct SelfBuildApp: App {
    @StateObject private var store: AppStore
    @StateObject private var gemini: GeminiClient
    @StateObject private var router: Router
    @StateObject private var nexus: NexusSession
    @StateObject private var rest = RestTimer()

    init() {
        let s = AppStore()
        let g = GeminiClient()
        let r = Router()
        _store = StateObject(wrappedValue: s)
        _gemini = StateObject(wrappedValue: g)
        _router = StateObject(wrappedValue: r)
        _nexus = StateObject(wrappedValue: NexusSession(store: s, gemini: g, router: r))
        _ = NotificationManager.shared    // installe le délégué (boutons « Fait » / « +10 min ») dès le lancement
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(gemini)
                .environmentObject(router)
                .environmentObject(rest)
                .environmentObject(nexus)
                .preferredColorScheme(.dark)
                .tint(.white)
        }
    }
}
