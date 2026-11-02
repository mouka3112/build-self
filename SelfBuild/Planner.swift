import Foundation

/// Planning vivant : fonctions PURES (aucun état, aucun acteur) utilisées par ActionEngine,
/// le Hub et l'aperçu des propositions de Nexus. Même entrée → même résultat,
/// donc une proposition « Appliquer ce planning » donne exactement le planning affiché.
enum Planner {

    // MARK: Statut des tâches
    /// Heure limite de la journée (coucher), exprimée en minutes depuis minuit (peut dépasser 1440).
    static func limit(bed: Int) -> Int { bed < 12 * 60 ? bed + 1440 : bed }

    /// Tâche flexible jamais démarrée dont l'heure est largement passée : « manquée » (affichée à part, jamais déplacée seule).
    static func isMissed(_ t: TaskItem, now: Int) -> Bool {
        guard !t.done, t.startedAt == nil, t.kind != .school, t.kind != .sleep else { return false }
        return t.end + 30 < now
    }
    /// Un cours dont l'heure de fin est passée disparaît automatiquement.
    static func isPastClass(_ t: TaskItem, now: Int) -> Bool { t.kind == .school && t.end <= now }

    /// Tâches encore à faire, dans l'ordre : la première est « en cours » ou « à venir ».
    static func active(_ tasks: [TaskItem], now: Int) -> [TaskItem] {
        tasks.filter { !$0.done && !isPastClass($0, now: now) && !isMissed($0, now: now) }.sorted { $0.start < $1.start }
    }
    static func missed(_ tasks: [TaskItem], now: Int) -> [TaskItem] {
        tasks.filter { isMissed($0, now: now) }.sorted { $0.start < $1.start }
    }

    // MARK: Réorganisation
    /// Décale les tâches flexibles restantes pour qu'aucune ne commence avant `now` ni ne chevauche
    /// un ancrage (cours, cours particulier, sommeil, tâche démarrée ou épinglée).
    /// Une tâche qui ne rentre plus avant le coucher est retirée et renvoyée dans `dropped`.
    static func reflow(_ tasks: [TaskItem], from now: Int, limit: Int, pinned: Set<UUID> = [], clock: Int? = nil) -> (tasks: [TaskItem], dropped: [TaskItem]) {
        let realNow = clock ?? now
        func isAnchor(_ t: TaskItem) -> Bool { t.isFixed || pinned.contains(t.id) || t.startedAt != nil }
        let open = tasks.filter { !$0.done }
        let anchors: [(Int, Int)] = open.filter { isAnchor($0) && $0.end > now }.map { ($0.start, $0.end) }
        let movable = open.filter { !isAnchor($0) && !isMissed($0, now: realNow) }.sorted { $0.start < $1.start }
        let movableIDs = Set(movable.map(\.id))

        var cursor = now
        var placed: [TaskItem] = []
        var dropped: [TaskItem] = []
        for var t in movable {
            var s = max(t.start, cursor)
            var moved = true
            var guardCount = 0
            while moved && guardCount < 60 {
                moved = false
                guardCount += 1
                for b in anchors where s < b.1 && s + t.duration > b.0 {
                    s = b.1
                    moved = true
                }
            }
            if s >= limit { dropped.append(t); continue }
            t.start = s
            cursor = s + t.duration
            placed.append(t)
        }
        let kept = tasks.filter { !movableIDs.contains($0.id) }
        return ((kept + placed).sorted { $0.start < $1.start }, dropped)
    }

    /// Applique les créneaux proposés par Nexus, puis réorganise sans chevauchement.
    static func replan(_ tasks: [TaskItem], slots: [PlanSlot], now: Int, limit: Int)
        -> (tasks: [TaskItem], moved: [UUID], unknown: [String], dropped: [TaskItem]) {
        var ts = tasks
        var moved: [UUID] = []
        var unknown: [String] = []
        for s in slots {
            guard let i = match(s.ref, in: ts, now: now, includeDone: false), !ts[i].isFixed else {
                unknown.append(s.ref); continue
            }
            ts[i].start = max(0, s.start)
            if let d = s.duration, (5...600).contains(d) { ts[i].duration = d }
            ts[i].startedAt = nil
            moved.append(ts[i].id)
        }
        let r = reflow(ts, from: now, limit: limit)
        return (r.tasks, moved, unknown, r.dropped)
    }

    // MARK: Retrouver une tâche à partir d'un identifiant ou de mots-clés
    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    private static let stopWords: Set<String> = ["mes", "les", "des", "une", "fini", "finir", "termine", "terminee", "terminer",
                                                "faire", "fait", "avec", "pour", "dans", "tache", "maintenant", "commence",
                                                "commencer", "demarre", "demarrer", "suis", "vais", "viens", "deja", "tout", "toute"]

    private static func kindWords(_ k: TaskKind) -> [String] {
        switch k {
        case .workout: return ["muscu", "musculation", "seance", "entrainement", "gym", "salle"]
        case .meal: return ["repas", "manger", "dejeuner", "diner", "petit", "gouter", "mange"]
        case .study: return ["devoirs", "devoir", "revision", "revisions", "reviser", "etudes", "etudier", "bosser"]
        case .hygiene: return ["hygiene"]
        case .sleep: return ["dormir", "sommeil", "coucher", "dodo"]
        case .school: return ["ecole", "lycee", "college", "classe"]
        case .tutor: return ["prof", "particulier", "particuliers"]
        case .rest: return ["recuperation", "marche", "etirements", "repos"]
        case .other: return []
        }
    }

    /// Renvoie l'index de la tâche désignée par un UUID, un identifiant court (#3F2A) ou des mots-clés.
    static func match(_ ref: String, in tasks: [TaskItem], now: Int, includeDone: Bool) -> Int? {
        let r = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !r.isEmpty else { return nil }
        if let u = UUID(uuidString: r), let i = tasks.firstIndex(where: { $0.id == u }) { return i }
        let short = r.replacingOccurrences(of: "#", with: "").uppercased()
        if short.count == 4, let i = tasks.firstIndex(where: { $0.shortID == short }) { return i }

        let words = normalize(r).split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .filter { $0.count > 2 && !stopWords.contains($0) }
        guard !words.isEmpty else { return nil }

        var best: (index: Int, score: Int, pending: Bool, distance: Int)?
        for i in tasks.indices {
            let t = tasks[i]
            if t.done && !includeDone { continue }
            let title = normalize(t.title)
            let kw = kindWords(t.kind)
            var score = 0
            for w in words {
                if title.contains(w) { score += 3 }
                else if kw.contains(w) { score += 2 }
                else if w.count > 4, title.contains(String(w.prefix(w.count - 1))) { score += 1 }   // pluriel / accord
            }
            guard score > 0 else { continue }
            let cand = (index: i, score: score, pending: !t.done, distance: abs(t.start - now))
            if let b = best {
                let better = cand.score > b.score
                    || (cand.score == b.score && cand.pending && !b.pending)
                    || (cand.score == b.score && cand.pending == b.pending && cand.distance < b.distance)
                if better { best = cand }
            } else {
                best = cand
            }
        }
        return best?.index
    }

    // MARK: Génération de la journée type
    static func generate(date: Date, profile: UserProfile, workoutIndex: Int, timetable: [TimetableEntry],
                         exams: [ExamItem], homework: [Homework], tutors: [Tutor]) -> [TaskItem] {
        let cal = Calendar.current
        let wd = cal.component(.weekday, from: date)               // 1 = dimanche
        let wake = profile.wakeMinute
        let bed = limit(bed: profile.bedMinute)
        let todays = timetable.filter { $0.weekday == wd }.sorted { $0.start < $1.start }
        let isSchool = profile.isStudent && (!todays.isEmpty || (timetable.isEmpty && (2...6).contains(wd)))
        let trains = profile.trainingDays.contains(wd)
        let hairDay = [1, 2, 5].contains(wd)                       // dimanche, lundi, jeudi
        let day = Program.days[workoutIndex % Program.days.count]
        let today0 = cal.startOfDay(for: date)
        func daysUntil(_ d: Date) -> Int { cal.dateComponents([.day], from: today0, to: cal.startOfDay(for: d)).day ?? 99 }

        var t: [TaskItem] = []
        func add(_ title: String, _ icon: String, _ start: Int, _ dur: Int, _ kind: TaskKind, habit: String? = nil, link: UUID? = nil) {
            t.append(TaskItem(title: title, icon: icon, start: start, duration: dur, kind: kind, habit: habit, linkID: link))
        }

        add("Réveil & petit-déjeuner", "sunrise.fill", wake, 30, .meal)
        add("Dents (matin)", "sparkles", wake + 30, 5, .hygiene, habit: HygieneHabit.teethAM.rawValue)
        add("Visage (matin)", "face.smiling", wake + 35, 5, .hygiene, habit: HygieneHabit.faceAM.rawValue)

        let dueSoon = homework.filter { !$0.done && (0...2).contains(daysUntil($0.due)) }.map(\.subject)
        let subjects = Array(Set(dueSoon)).sorted().prefix(3)
        let hwTitle = subjects.isEmpty ? "Devoirs" : "Devoirs : " + subjects.joined(separator: ", ")
        let soonExams = exams.map { ($0, daysUntil($0.date)) }.filter { (0...3).contains($0.1) }.sorted { $0.1 < $1.1 }

        var gymStart: Int
        var revisionStart: Int
        if isSchool {
            if todays.isEmpty {
                add("Cours", "graduationcap.fill", 8 * 60, 8 * 60, .school)
            } else {
                for e in todays { add("Cours : \(e.subject)", "graduationcap.fill", e.start, max(15, e.end - e.start), .school) }
            }
            let out = todays.map(\.end).max() ?? 16 * 60
            add("Goûter protéiné", "fork.knife", out + 15, 30, .meal)
            add("Photos des cours du jour 📸", "camera.fill", out + 45, 5, .other)
            add(hwTitle, "book.fill", out + 50, 90, .study)
            gymStart = max(out + 150, 18 * 60 + 30)
            add("Dîner", "fork.knife", 20 * 60, 40, .meal)
            revisionStart = 20 * 60 + 40
            if soonExams.isEmpty { add("Révisions / lecture", "text.book.closed.fill", revisionStart, 40, .study) }
        } else {
            add(soonExams.isEmpty ? "Révisions longues" : "Révisions", "book.fill", wake + 90, 120, .study)
            add("Déjeuner", "fork.knife", 12 * 60 + 30, 60, .meal)
            add(hwTitle == "Devoirs" ? "Devoirs / avance sur la semaine" : hwTitle, "text.book.closed.fill", 14 * 60, 90, .study)
            gymStart = 16 * 60
            add("Dîner", "fork.knife", 19 * 60 + 30, 45, .meal)
            add("Préparer la semaine", "checklist", 20 * 60 + 30, 30, .other)
            revisionStart = 10 * 60
        }

        if trains {
            add("Musculation – \(day.code) \(day.name)", "dumbbell.fill", gymStart, 75, .workout)
        } else {
            add("Récupération active (marche + étirements)", "figure.walk", gymStart, 45, .rest)
        }
        let afterGym = gymStart + (trains ? 75 : 45)
        add("Douche", "shower.fill", afterGym, 15, .hygiene, habit: HygieneHabit.shower.rawValue)
        if hairDay { add("Soin des cheveux", "drop.fill", afterGym + 15, 10, .hygiene, habit: HygieneHabit.hair.rawValue) }

        for (e, d) in soonExams.prefix(2) {
            add("Réviser \(e.subject) – contrôle \(examLabel(d))", "text.book.closed.fill", revisionStart, 45, .study, link: e.id)
        }
        for tu in tutors where tu.weekday == wd {
            add("Cours particulier : \(tu.subject) (\(tu.name))", "person.2.fill", tu.hour * 60 + tu.minute, 60, .tutor, link: tu.id)
        }

        add("Dents (soir)", "sparkles", bed - 30, 5, .hygiene, habit: HygieneHabit.teethPM.rawValue)
        add("Soin visage (soir)", "face.smiling", bed - 25, 5, .hygiene, habit: HygieneHabit.facePM.rawValue)
        add("Préparer demain + bilan avec Nexus", "checklist", bed - 15, 15, .other)
        let sleep = max(240, wake + 1440 - bed)
        add("Sommeil (\(sleep / 60) h)", "moon.zzz.fill", bed, sleep, .sleep)

        return reflow(t, from: 0, limit: bed).tasks
    }

    static func examLabel(_ days: Int) -> String {
        days == 0 ? "aujourd'hui" : days == 1 ? "demain" : "dans \(days) j"
    }

    static func icon(for kind: TaskKind) -> String {
        switch kind {
        case .school: return "graduationcap.fill"
        case .study: return "book.fill"
        case .workout: return "dumbbell.fill"
        case .meal: return "fork.knife"
        case .sleep: return "moon.zzz.fill"
        case .rest: return "figure.walk"
        case .hygiene: return "sparkles"
        case .other: return "bolt.fill"
        case .tutor: return "person.2.fill"
        }
    }
}

/// Formats lisibles (français) partagés par le moteur, le Hub et le contexte IA.
enum Fmt {
    static func money(_ v: Double, _ currency: String) -> String {
        String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",") + " " + currency
    }
    static func signedMoney(_ v: Double, _ currency: String) -> String {
        (v < 0 ? "−" : "+") + money(abs(v), currency)
    }
    static func dayMonth(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "EEE d MMM"
        return f.string(from: d)
    }
    static func reminderRule(_ date: Date, _ rule: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm"
        let hm = f.string(from: date)
        switch rule {
        case "daily": return "chaque jour à \(hm)"
        case "weekly":
            f.dateFormat = "EEEE"
            return "chaque \(f.string(from: date)) à \(hm)"
        case "monthly": return "le \(Calendar.current.component(.day, from: date)) de chaque mois à \(hm)"
        default:
            f.dateFormat = "EEEE d MMMM 'à' HH:mm"
            return f.string(from: date)
        }
    }
    static func minutesOf(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
    static func dateAt(minute: Int, on day: Date = .now) -> Date {
        Calendar.current.date(byAdding: .minute, value: minute, to: Calendar.current.startOfDay(for: day)) ?? day
    }
}
