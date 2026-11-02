import Foundation
import UserNotifications

/// Notifications soignées : emoji, vignette Nexus, boutons « ✅ Fait » / « ⏰ +10 min », niveau urgent.
/// Note : `.timeSensitive` sans l'entitlement payant « Time Sensitive Notifications » peut être rétrogradé par iOS en simple alerte.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        let done = UNNotificationAction(identifier: "DONE", title: "✅ Fait", options: [])
        let snooze = UNNotificationAction(identifier: "SNOOZE10", title: "⏰ +10 min", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "NEXUS", actions: [done, snooze], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "NEXUS_INFO", actions: [snooze], intentIdentifiers: [], options: [])
        ])
    }

    func requestAuthorization() async { _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge]) }

    private func content(title: String, body: String, urgent: Bool = true, taskID: UUID? = nil) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body
        c.sound = .default
        c.categoryIdentifier = taskID == nil ? "NEXUS_INFO" : "NEXUS"
        c.threadIdentifier = "selfbuild"
        if let taskID { c.userInfo = ["taskID": taskID.uuidString] }
        c.interruptionLevel = urgent ? .timeSensitive : .active
        c.relevanceScore = urgent ? 1.0 : 0.5
        // Vignette Nexus : iOS déplace le fichier joint, on lui donne donc une copie temporaire.
        if let src = Bundle.main.url(forResource: "nexus", withExtension: "png") {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-\(UUID().uuidString).png")
            if (try? FileManager.default.copyItem(at: src, to: tmp)) != nil,
               let att = try? UNNotificationAttachment(identifier: "nexus", url: tmp, options: nil) { c.attachments = [att] }
        }
        return c
    }

    func schedule(id: String, title: String, body: String, in seconds: TimeInterval) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content(title: title, body: body), trigger: trigger))
    }

    /// Notification aujourd'hui à `minute` (minutes depuis minuit), ignorée si déjà passée.
    func schedule(id: String, title: String, body: String, atMinute minute: Int, taskID: UUID? = nil) {
        let c = Calendar.current
        let now = c.dateComponents([.hour, .minute], from: .now)
        guard minute > (now.hour ?? 0) * 60 + (now.minute ?? 0), minute < 1440 else { return }
        var d = c.dateComponents([.year, .month, .day], from: .now)
        d.hour = minute / 60; d.minute = minute % 60
        center.add(UNNotificationRequest(identifier: id, content: content(title: title, body: body, taskID: taskID),
                                         trigger: UNCalendarNotificationTrigger(dateMatching: d, repeats: false)))
    }

    func schedule(id: String, title: String, body: String, date: Date) {
        guard date > .now else { return }
        let d = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        center.add(UNNotificationRequest(identifier: id, content: content(title: title, body: body),
                                         trigger: UNCalendarNotificationTrigger(dateMatching: d, repeats: false)))
    }

    func cancel(id: String) { center.removePendingNotificationRequests(withIdentifiers: [id]) }

    // MARK: Rappels personnalisés (avec répétition)
    func scheduleReminder(_ r: UserReminder, name: String = "toi") {
        let cal = Calendar.current
        var comps: DateComponents
        var repeats = true
        switch r.repeatRule {
        case "daily": comps = cal.dateComponents([.hour, .minute], from: r.date)
        case "weekly": comps = cal.dateComponents([.weekday, .hour, .minute], from: r.date)
        case "monthly": comps = cal.dateComponents([.day, .hour, .minute], from: r.date)
        default:
            comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: r.date)
            repeats = false
            if r.date <= .now { return }
        }
        center.add(UNNotificationRequest(identifier: "rem-\(r.id)",
                                         content: content(title: "🔔 \(r.title)", body: "Rappel de Nexus – c'est le moment, \(name).", urgent: r.urgent),
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: repeats)))
    }
    func cancelReminder(_ id: UUID) { cancel(id: "rem-\(id)") }

    // MARK: Cours particuliers : rappel 1 h avant (chaque semaine) + paiement le dernier jour du mois à 18 h
    func scheduleTutor(_ t: Tutor) {
        var d = DateComponents()
        let startMinute = t.hour * 60 + t.minute - 60
        d.weekday = startMinute >= 0 ? t.weekday : (t.weekday + 5) % 7 + 1
        d.hour = ((startMinute + 1440) % 1440) / 60; d.minute = ((startMinute + 1440) % 1440) % 60
        center.add(UNNotificationRequest(identifier: "tutor-\(t.id)",
                                         content: content(title: "📚 Cours avec \(t.name) dans 1 h", body: "\(t.subject) à \(timeString(t.hour * 60 + t.minute)). Prépare tes affaires."),
                                         trigger: UNCalendarNotificationTrigger(dateMatching: d, repeats: true)))
        let cal = Calendar.current
        for offset in 0..<3 {
            guard let month = cal.date(byAdding: .month, value: offset, to: .now),
                  let range = cal.range(of: .day, in: .month, for: month) else { continue }
            var e = cal.dateComponents([.year, .month], from: month)
            e.day = range.count; e.hour = 18; e.minute = 0
            guard let when = cal.date(from: e), when > .now else { continue }
            let pid = "pay-\(t.id)-\(e.year ?? 0)-\(e.month ?? 0)"
            center.add(UNNotificationRequest(identifier: pid,
                                             content: content(title: "💸 Paiement du prof", body: "Fin du mois : pense à payer \(t.name) (\(t.subject)). Appuie sur « Khallast » dans l'app."),
                                             trigger: UNCalendarNotificationTrigger(dateMatching: e, repeats: false)))
        }
    }
    func cancelTutor(_ t: Tutor) { cancel(id: "tutor-\(t.id)") }

    /// Rappels locaux pour chaque tâche + rappels proactifs rédigés par Gemini.
    /// Seuls les identifiants `task-` et `ai-` sont supprimés à la reprogrammation.
    @MainActor
    func refreshProactive(store: AppStore, gemini: GeminiClient) async {
        let pendingIds = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pendingIds.filter { $0.hasPrefix("task-") || $0.hasPrefix("ai-") })
        let name = store.displayName
        for t in store.pending where t.kind != .sleep && t.kind != .school {
            schedule(id: "task-\(t.id)", title: "\(emoji(t.kind)) \(t.title)", body: "C'est l'heure, \(name) ! \(t.duration) min.",
                     atMinute: t.start, taskID: t.id)
        }
        for t in store.tutors { scheduleTutor(t) }
        for r in store.reminders { scheduleReminder(r, name: name) }
        guard !gemini.apiKey.isEmpty, let items = try? await gemini.proactiveReminders(store: store) else { return }
        for (i, r) in items.enumerated() {
            schedule(id: "ai-\(i)", title: r.title, body: r.body, atMinute: r.minute)
        }
    }

    private func emoji(_ k: TaskKind) -> String {
        switch k {
        case .workout: return "💪"
        case .meal: return "🍽️"
        case .study: return "📖"
        case .hygiene: return "🫧"
        case .rest: return "🚶"
        case .tutor: return "📚"
        case .sleep: return "🌙"
        case .school: return "🏫"
        case .other: return "⏰"
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        switch response.actionIdentifier {
        case "DONE":
            // « ✅ Fait » passe par le moteur d'actions : tâche cochée + effets croisés + Journal, comme dans l'app.
            if let id = content.userInfo["taskID"] as? String {
                Task { @MainActor in
                    _ = AppStore.current?.engine.apply(.completeTask(ref: id), source: .notification)
                    AppStore.current?.saveNow()
                }
            }
        case "SNOOZE10":
            if let c = content.mutableCopy() as? UNMutableNotificationContent {
                c.attachments = []
                center.add(UNNotificationRequest(identifier: "snooze-\(UUID().uuidString)", content: c,
                                                 trigger: UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)))
            }
        default:
            break
        }
        completionHandler()
    }
}
