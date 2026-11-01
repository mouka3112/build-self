import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var gemini: GeminiClient
    @EnvironmentObject var router: Router
    @EnvironmentObject var rest: RestTimer
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                SmartButton()
                TabView(selection: $router.selectedTab) {
                    HubView().tabItem { Label("Hub", systemImage: "scope") }.tag(0)
                    NexusView().tabItem { Label("Nexus", systemImage: "sparkles") }.tag(1)
                    WorkoutView().tabItem { Label("Muscu", systemImage: "dumbbell.fill") }.tag(2)
                    NutritionView().tabItem { Label("Nutrition", systemImage: "fork.knife") }.tag(3)
                    PlusView().tabItem { Label("Plus", systemImage: "square.grid.2x2.fill") }.tag(4)
                }
            }
        }
        .hideKeyboardOnTap()
        .sheet(item: $router.sheet) { d in
            NavigationStack {
                DestinationView(dest: d).hideKeyboardOnTap()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { router.sheet = nil } } }
            }
        }
        .sheet(item: $router.wrapUp) { r in WrapUpView(kind: r.kind) }
        .fullScreenCover(isPresented: Binding(get: { store.lockdownActive }, set: { _ in })) {
            LockdownView().hideKeyboardOnTap()
        }
        .task {
            await NotificationManager.shared.requestAuthorization()
            store.rolloverIfNeeded()
            await NotificationManager.shared.refreshProactive(store: store, gemini: gemini)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                if store.lockdownActive {
                    NotificationManager.shared.schedule(id: "lockdown", title: "🔒 Lockdown actif",
                                                        body: "Reviens sur SELF BUILD, tes devoirs t'attendent.", in: 15)
                }
            case .active:
                NotificationManager.shared.cancel(id: "lockdown")
                store.rolloverIfNeeded()
            default: break
            }
        }
    }
}

final class Router: ObservableObject {
    @Published var selectedTab = 0
    @Published var pendingPrompt: String?
    @Published var sheet: AppDestination?
    @Published var aiTarget: AppDestination?
    @Published var wrapUp: WrapUpRequest?
    /// Dernière modification faite par Nexus (affichée dans le Hub).
    @Published var lastAction: String?

    func go(_ d: AppDestination) {
        if let t = d.tabIndex { sheet = nil; selectedTab = t } else { sheet = d }
        if aiTarget == d { aiTarget = nil }
    }
}
