import ActivityKit
import Combine
import Foundation

@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()
    @Published private(set) var isActive = false
    /// Dernier message de diagnostic (affiché dans Réglages → Dynamic Island).
    @Published var status = ""

    /// L'extension (SelfBuildWidget.appex) est-elle bien installée dans l'app ?
    static var extensionInstalled: Bool {
        guard let url = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return false }
        return items.contains { $0.hasSuffix(".appex") }
    }
    static var activitiesAllowed: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    var diagnostic: String {
        var l: [String] = []
        l.append(Self.activitiesAllowed ? "✅ Live Activities autorisées" : "❌ Live Activities désactivées (Réglages iPhone → SELF BUILD → Activités en direct)")
        l.append(Self.extensionInstalled ? "✅ Extension Dynamic Island installée" : "❌ Extension absente : l'outil d'installation l'a retirée (voir guide)")
        l.append("Activités en cours : \(Activity<SelfBuildAttributes>.activities.count)")
        if !status.isEmpty { l.append(status) }
        return l.joined(separator: "\n")
    }

    func start(mode: String, title: String, subtitle: String, minutes: Int) {
        guard Self.activitiesAllowed else { status = "Live Activities désactivées dans les réglages de l'iPhone."; return }
        let end = Date().addingTimeInterval(Double(max(minutes, 1)) * 60)
        let state = SelfBuildAttributes.ContentState(title: title, subtitle: subtitle, endDate: end)
        Task {
            await endAll()
            do {
                _ = try Activity.request(attributes: SelfBuildAttributes(mode: mode),
                                         content: ActivityContent(state: state, staleDate: nil),
                                         pushType: nil)
                isActive = true
                status = "Activité lancée. Quitte l'app (écran d'accueil) pour la voir dans la Dynamic Island."
            } catch {
                status = "Échec : \(error.localizedDescription)"
            }
        }
    }

    func end() { Task { await endAll() } }

    private func endAll() async {
        for a in Activity<SelfBuildAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        isActive = false
    }
}
