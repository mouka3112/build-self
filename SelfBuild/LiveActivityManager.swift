import ActivityKit
import Combine
import Foundation

/// Live Activity / Dynamic Island « façon Duolingo » : Nexus à gauche, titre, gros compte à rebours.
/// iOS interdit les animations continues dans une Live Activity : on change seulement la pose de Nexus
/// toutes les ~8 s tant que l'app tourne (au premier plan, ou en arrière-plan pendant une course / de la musique).
@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()
    @Published private(set) var isActive = false
    /// Dernier message de diagnostic (affiché dans Réglages → Dynamic Island).
    @Published var status = ""
    private var animator: Task<Void, Never>?
    private var restTask: Task<Void, Never>?
    private var current: SelfBuildAttributes.ContentState?
    /// État « normal » (séance, focus) à restaurer après un minuteur de repos.
    private var base: SelfBuildAttributes.ContentState?

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
        l.append(Self.extensionInstalled ? "✅ Extension Dynamic Island présente (SelfBuildWidget.appex)" : "❌ Extension absente : l'outil d'installation l'a retirée (voir le guide, option « garder les extensions »)")
        l.append("Activités en cours : \(Activity<SelfBuildAttributes>.activities.count)")
        if !status.isEmpty { l.append(status) }
        return l.joined(separator: "\n")
    }

    func start(mode: String, title: String, subtitle: String, minutes: Int) {
        guard Self.activitiesAllowed else { status = "Live Activities désactivées dans les réglages de l'iPhone."; return }
        guard Self.extensionInstalled else { status = "Extension absente : impossible d'afficher la Dynamic Island."; return }
        let end = Date().addingTimeInterval(Double(max(minutes, 1)) * 60)
        let state = SelfBuildAttributes.ContentState(title: title, subtitle: subtitle, endDate: end, pose: "wave")
        Task {
            await endAll(final: nil)
            do {
                _ = try Activity.request(attributes: SelfBuildAttributes(mode: mode),
                                         content: ActivityContent(state: state, staleDate: end.addingTimeInterval(600)),
                                         pushType: nil)
                isActive = true
                current = state
                base = state
                status = "Activité lancée. Quitte l'app (écran d'accueil ou verrouillé) pour la voir."
                startAnimator()
            } catch {
                status = "Échec de Activity.request : \(error.localizedDescription)"
            }
        }
    }

    /// Minuteur de repos (musculation) affiché dans la Dynamic Island, puis retour à la séance.
    func showRest(seconds: Int) {
        guard isActive, let b = base else { return }
        let rest = SelfBuildAttributes.ContentState(title: "Repos ⏱️", subtitle: "Prochaine série : \(b.title)",
                                                    endDate: Date().addingTimeInterval(Double(seconds)), pose: "blink")
        push(rest)
        restTask?.cancel()
        restTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(seconds)))
            guard let self, !Task.isCancelled, var back = self.base else { return }
            back.pose = "happy"
            self.push(back)
        }
    }

    /// Termine l'activité. Avec un message, Nexus affiche « Terminé » content quelques secondes.
    func end(message: String? = nil) {
        let msg = message
        Task { await endAll(final: msg) }
    }

    /// Change la pose de Nexus (coucou, regard à gauche/droite, clin d'œil, content).
    func setPose(_ pose: String) {
        guard var st = current else { return }
        st.pose = pose
        push(st)
    }

    private func push(_ st: SelfBuildAttributes.ContentState) {
        current = st
        Task {
            for a in Activity<SelfBuildAttributes>.activities {
                await a.update(ActivityContent(state: st, staleDate: st.endDate.addingTimeInterval(600)))
            }
        }
    }

    private func startAnimator() {
        animator?.cancel()
        animator = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            let cycle = ["idle", "lookL", "idle", "lookR", "blink", "idle", "happy", "idle"]
            var i = 0
            while !Task.isCancelled {
                self?.setPose(cycle[i % cycle.count])
                i += 1
                try? await Task.sleep(for: .seconds(8))
            }
        }
    }

    private func endAll(final message: String?) async {
        animator?.cancel(); animator = nil
        restTask?.cancel(); restTask = nil
        let last = current
        current = nil; base = nil
        for a in Activity<SelfBuildAttributes>.activities {
            if let message, let last {
                var done = last
                done.title = message; done.subtitle = "Bien joué 💪"; done.pose = "happy"; done.finished = true
                await a.end(ActivityContent(state: done, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(8)))
            } else {
                await a.end(nil, dismissalPolicy: .immediate)
            }
        }
        isActive = false
    }
}
