import Foundation
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    override init() { super.init(); center.delegate = self }

    func requestAuthorization() async { _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge]) }

    func schedule(id: String, title: String, body: String, in seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Notification aujourd'hui à `minute` (minutes depuis minuit), ignorée si déjà passée.
    func schedule(id: String, title: String, body: String, atMinute minute: Int) {
        let c = Calendar.current
        let now = c.dateComponents([.hour, .minute], from: .now)
        guard minute > (now.hour ?? 0) * 60 + (now.minute ?? 0), minute < 1440 else { return }
        var d = c.dateComponents([.year, .month, .day], from: .now)
        d.hour = minute / 60; d.minute = minute % 60
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: d, repeats: false)))
    }

    func schedule(id: String, title: String, body: String, date: Date) {
        guard date > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        let d = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        center.add(UNNotificationRequest(identifier: id, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: d, repeats: false)))
    }

    func cancel(id: String) { center.removePendingNotificationRequests(withIdentifiers: [id]) }

    /// Rappels locaux pour chaque tâche + rappels proactifs rédigés par Gemini (si clé API présente).
    @MainActor
    func refreshProactive(store: AppStore, gemini: GeminiClient) async {
        let pendingIds = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pendingIds.filter { $0.hasPrefix("task-") || $0.hasPrefix("ai-") })
        for t in store.pending where t.kind != .sleep && t.kind != .school {
            schedule(id: "task-\(t.id)", title: "C'est l'heure", body: t.title, atMinute: t.start)
        }
        guard !gemini.apiKey.isEmpty, let items = try? await gemini.proactiveReminders(store: store) else { return }
        for (i, r) in items.enumerated() {
            schedule(id: "ai-\(i)", title: r.title, body: r.body, atMinute: r.minute)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
