import SwiftUI

@main
struct SelfBuildApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var gemini = GeminiClient()
    @StateObject private var router = Router()
    @StateObject private var rest = RestTimer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(gemini)
                .environmentObject(router)
                .environmentObject(rest)
                .preferredColorScheme(.dark)
                .tint(.white)
        }
    }
}
