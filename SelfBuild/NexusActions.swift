import Foundation

struct PlanItem: Decodable { let title: String; let start: String; let duration: Int? }

struct NexusAction: Decodable {
    let type: String
    let amount: Double?; let category: String?; let note: String?
    let items: [MealItem]?
    let ml: Double?; let habit: String?
    let title: String?; let minutes: Int?
    let tasks: [PlanItem]?
    let date: String?; let repeatRule: String?
    let subject: String?; let topic: String?
    enum CodingKeys: String, CodingKey {
        case type, amount, category, note, items, ml, habit, title, minutes, tasks, date, subject, topic
        case repeatRule = "repeat"
    }
}

/// Transforme les « tags » écrits par Nexus en vraies modifications de l'app (Finances, Nutrition, planning…).
enum NexusActions {
    /// Texte sans tags (aussi pendant le streaming : une balise encore incomplète est masquée).
    static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"(?s)\[\[(ACT|GOTO):.*?\]\]"#, with: "", options: .regularExpression)
        if let r = t.range(of: "[[") { t = String(t[..<r.lowerBound]) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extract(_ s: String) -> (clean: String, actions: [NexusAction], goto: AppDestination?) {
        var actions: [NexusAction] = []
        if let regex = try? NSRegularExpression(pattern: #"\[\[ACT:(.*?)\]\]"#, options: [.dotMatchesLineSeparators]) {
            let ns = s as NSString
            for m in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                let json = ns.substring(with: m.range(at: 1))
                if let d = json.data(using: .utf8), let a = try? JSONDecoder().decode(NexusAction.self, from: d) { actions.append(a) }
            }
        }
        var goto: AppDestination?
        if let r = s.range(of: #"\[\[GOTO:([a-z]+)\]\]"#, options: .regularExpression) {
            let tag = String(s[r]).replacingOccurrences(of: "[[GOTO:", with: "").replacingOccurrences(of: "]]", with: "")
            goto = AppDestination(rawValue: tag)
        }
        return (clean(s), actions, goto)
    }

    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd"] { f.dateFormat = fmt; if let d = f.date(from: s) { return d } }
        return nil
    }
    private static func minutes(_ s: String) -> Int? {
        let p = s.split(separator: ":").compactMap { Int($0) }
        return p.count == 2 ? p[0] * 60 + p[1] : nil
    }

    /// Applique une action et renvoie un texte de confirmation (nil si rien n'a été fait).
    @MainActor
    static func apply(_ a: NexusAction, store: AppStore) -> String? {
        switch a.type {
        case "expense":
            guard let amt = a.amount, amt > 0 else { return nil }
            let cat = Finance.categories.map(\.name).contains(a.category ?? "") ? (a.category ?? "Autre") : "Autre"
            store.txns.append(Txn(date: .now, amount: -amt, category: cat, note: a.note ?? ""))
            return "Ajouté dans Finances : −\(String(format: "%.2f", amt)) TND (\(cat))"
        case "income":
            guard let amt = a.amount, amt > 0 else { return nil }
            store.txns.append(Txn(date: .now, amount: amt, category: "Revenu", note: a.note ?? "Argent reçu"))
            return "Ajouté dans Finances : +\(String(format: "%.2f", amt)) TND"
        case "meal":
            guard let items = a.items, !items.isEmpty else { return nil }
            for i in items {
                store.foods.append(FoodEntry(date: .now, name: i.name, grams: i.grams, kcal: i.kcal, protein: i.protein))
                store.ensureCard(name: i.name, grams: i.grams, kcal: i.kcal, protein: i.protein)
            }
            let kcal = Int(items.reduce(0) { $0 + $1.kcal }), prot = Int(items.reduce(0) { $0 + $1.protein })
            return "Ajouté dans Nutrition : \(items.map(\.name).joined(separator: ", ")) ≈ \(kcal) kcal, \(prot) g de protéines (estimation)"
        case "water":
            let n = max(1, Int(((a.ml ?? 250) / 250).rounded()))
            for _ in 0..<n { store.healthLog.append(HealthEntry(date: .now, kind: "Eau", text: "250 ml")) }
            return "Eau enregistrée : \(n * 250) ml"
        case "hygiene":
            guard let h = HygieneHabit(rawValue: a.habit ?? "") else { return nil }
            store.setHygiene(h, true)
            return "Hygiène validée : \(h.title)"
        case "task_done":
            guard let t = store.findPending(a.title ?? "") else { return nil }
            store.complete(t)
            return "Tâche terminée : \(t.title)"
        case "start_task":
            guard let t = store.findPending(a.title ?? "") else { return nil }
            store.startNow(t)
            return "Tâche démarrée maintenant : \(t.title)"
        case "switch":
            guard let title = a.title else { return nil }
            store.switchActivity(title: title, minutes: a.minutes ?? 30)
            return "Planning réorganisé (\(title), \(a.minutes ?? 30) min)"
        case "replan":
            let items: [(title: String, start: Int, duration: Int?)] = (a.tasks ?? []).compactMap { p in
                guard let m = minutes(p.start) else { return nil }
                return (p.title, m, p.duration)
            }
            guard !items.isEmpty else { return nil }
            store.applyPlan(items)
            return "Planning du jour réorganisé par Nexus"
        case "reminder":
            guard let title = a.title, let date = parseDate(a.date) else { return nil }
            let rule = ["daily", "weekly", "monthly"].contains(a.repeatRule ?? "") ? (a.repeatRule ?? "none") : "none"
            let r = UserReminder(title: title, date: date, repeatRule: rule)
            store.reminders.append(r)
            NotificationManager.shared.scheduleReminder(r)
            let when = date.formatted(date: .abbreviated, time: .shortened)
            let rep = rule == "daily" ? ", chaque jour" : rule == "weekly" ? ", chaque semaine" : rule == "monthly" ? ", chaque mois" : ""
            return "Rappel programmé : \(title) – \(when)\(rep)"
        case "exam":
            guard let subject = a.subject, let date = parseDate(a.date) else { return nil }
            store.exams.append(ExamItem(subject: subject, date: date, topic: a.topic ?? ""))
            return "Contrôle ajouté : \(subject) le \(date.formatted(date: .abbreviated, time: .omitted))"
        case "homework":
            guard let subject = a.subject else { return nil }
            store.homework.append(Homework(subject: subject, title: a.topic ?? "Devoir", due: parseDate(a.date) ?? Date().addingTimeInterval(86400)))
            return "Devoir ajouté : \(subject)"
        default:
            return nil
        }
    }
}
