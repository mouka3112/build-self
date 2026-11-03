import Foundation

// MARK: - Actions typées (UI, Nexus et notifications parlent le même langage)
enum AppAction: Codable, Hashable {
    case expense(amount: Double, category: String, note: String)
    case income(amount: Double, note: String)
    case meal(items: [MealLine])
    case water(ml: Int)
    case hygiene(habits: [HygieneHabit])
    case completeTask(ref: String)
    case startTask(ref: String)
    case addTask(title: String, start: Int, duration: Int, kind: TaskKind)
    case removeTask(ref: String)
    case replanDay(slots: [PlanSlot])
    case switchActivity(title: String, minutes: Int)
    case workoutSet(exercise: String, weight: Double, reps: Int, effort: Int?)
    case health(kind: String, text: String)
    case note(text: String)
    case reminder(title: String, date: Date, rule: String, urgent: Bool)
    case exam(subject: String, date: Date, topic: String)
    case homework(subject: String, title: String, due: Date)
    case completeHomework(ref: String)
    case tutorSession(ref: String)
    case tutorPaid(ref: String)
    case completeChallenge(ref: String)
    case undoLast
    case navigate(to: AppDestination)
    // Lot 2 : actions génériques des modules (ajout / modification / suppression annulables)
    case add(Record)
    case update(Record)
    case delete(RecordRef)
    case reopenHomework(id: UUID)
    case reopenChallenge(id: UUID)
    case finishWorkout
    case setLockdown(minutes: Int?)

    /// Empreinte stable : sert à l'anti-doublon.
    var fingerprint: String { String(describing: self) }

    /// Actions qui AJOUTENT une donnée (un doublon = une vraie erreur). Les autres sont idempotentes par nature.
    var isAdditive: Bool {
        switch self {
        case .expense, .income, .meal, .water, .workoutSet, .health, .note, .reminder, .exam, .homework, .addTask, .switchActivity, .add:
            return true
        default:
            return false
        }
    }

    /// Petites modifications d'UI (cocher un habit, une étape…) : passent par le moteur mais ne remplissent pas le Journal.
    var isQuiet: Bool {
        switch self {
        case .update(let r):
            if case .challenge = r { return false }
            return true
        case .setLockdown:
            return true
        default:
            return false
        }
    }

    var proposalLabel: String {
        switch self {
        case .replanDay: return "Appliquer ce planning"
        case .reminder: return "Ajouter ce rappel"
        case .addTask: return "Ajouter au planning"
        case .removeTask: return "Retirer du planning"
        case .exam: return "Ajouter ce contrôle"
        case .homework: return "Ajouter ce devoir"
        case .switchActivity: return "Décaler ma journée"
        default: return "Appliquer"
        }
    }
}

enum ActionSource: String, Codable { case nexus, ui, notification }
enum ActionStatus: String, Codable { case applied, duplicate, rejected, proposed, dismissed, undone }

/// Opération inverse, persistée : le bouton « Annuler » fonctionne même après redémarrage de l'app.
enum UndoOp: Codable, Hashable {
    case removeTxn(UUID)
    case removeFoods([UUID])
    case removeCustomFoods([String])
    case setTaskDone(UUID, Bool)
    case restoreTimings([TaskTiming])
    case removeTask(UUID)
    case insertTask(TaskItem)
    case removeHygiene([UUID])
    case removeHealth([UUID])
    case removeSet(UUID)
    case removeNote(UUID)
    case removeReminder(UUID)
    case removeExam(UUID)
    case removeHomework(UUID)
    case setHomeworkDone(UUID, Bool)
    case removeTutorSession(UUID)
    case setTutorSessionsPaid([UUID], Bool)
    case setChallengeDone(UUID, Bool)
    case setWorkoutCursor(Int)
    case remove(RecordRef)
    case upsert(Record)
}

struct ActionResult: Hashable {
    var status: ActionStatus
    var summary: String
    var destination: AppDestination? = nil
    var undo: [UndoOp] = []

    static func rejected(_ why: String) -> ActionResult { ActionResult(status: .rejected, summary: why) }
}

/// Une ligne du Journal Nexus : ce qui a VRAIMENT été fait (ou refusé, ou proposé).
struct JournalItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var action: AppAction?
    var tool: String?
    var status: ActionStatus
    var summary: String
    var destination: AppDestination?
    var undo: [UndoOp] = []
    var fingerprint = ""

    var canUndo: Bool { status == .applied && !undo.isEmpty }
}

struct JournalEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var source: ActionSource
    var userText: String?
    var aiText: String?
    var items: [JournalItem]

    var isError: Bool { aiText?.hasPrefix("⚠️") ?? false }
    var proposals: [JournalItem] { items.filter { $0.status == .proposed } }
}

/// Ce que Nexus demande, après validation des arguments (NexusTools).
enum PlannedAction {
    case run(AppAction)
    case propose(AppAction)
    case invalid(tool: String, reason: String)
}

// MARK: - Moteur d'actions
@MainActor
final class ActionEngine {
    unowned let store: AppStore
    init(store: AppStore) { self.store = store }

    private var now: Int { store.minutesNow }
    private var cal: Calendar { Calendar.current }

    // MARK: API publique
    /// Point d'entrée unique pour l'UI. Journalise l'action (avec « Annuler »).
    @discardableResult
    func apply(_ action: AppAction) -> ActionResult { apply(action, source: .ui) }

    @discardableResult
    func apply(_ action: AppAction, source: ActionSource) -> ActionResult {
        let r = run(action)
        if case .navigate = action { return r }
        if action.isQuiet && r.status == .applied { return r }
        record(JournalEntry(source: source, items: [makeItem(action, r)]))
        return r
    }

    /// Un tour de Nexus : exécute ce qui est affirmé, propose ce qui est ambigu, refuse ce qui est invalide.
    func perform(_ planned: [PlannedAction], userText: String, aiText: String) -> JournalEntry {
        var items: [JournalItem] = []
        var seen = Set<String>()
        for p in planned {
            switch p {
            case .invalid(let tool, let reason):
                items.append(JournalItem(action: nil, tool: tool, status: .rejected, summary: "Refusé (\(tool)) : \(reason)"))
            case .run(let a):
                guard seen.insert(a.fingerprint).inserted else { continue }
                if a.isAdditive && recentlyApplied(a.fingerprint, within: 600) {
                    items.append(makeItem(a, ActionResult(status: .duplicate, summary: "Doublon ignoré : déjà enregistré il y a quelques minutes")))
                    continue
                }
                items.append(makeItem(a, run(a)))
            case .propose(let a):
                guard seen.insert(a.fingerprint).inserted else { continue }
                if let why = validate(a) {
                    items.append(makeItem(a, .rejected(why)))
                } else {
                    items.append(makeItem(a, ActionResult(status: .proposed, summary: preview(a), destination: destination(of: a))))
                }
            }
        }
        let trimmed = aiText.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.isEmpty ? fallbackText(items) : trimmed
        let entry = JournalEntry(source: .nexus, userText: String(userText.prefix(160)), aiText: text, items: items)
        record(entry)
        return entry
    }

    @discardableResult
    func applyProposal(entryID: UUID, itemID: UUID) -> ActionResult? {
        guard let loc = locate(entryID, itemID) else { return nil }
        let item = store.journal[loc.0].items[loc.1]
        guard item.status == .proposed, let a = item.action else { return nil }
        let r = run(a)
        store.journal[loc.0].items[loc.1].status = r.status
        store.journal[loc.0].items[loc.1].summary = r.summary
        store.journal[loc.0].items[loc.1].undo = r.undo
        store.journal[loc.0].items[loc.1].destination = r.destination
        return r
    }

    func dismissProposal(entryID: UUID, itemID: UUID) {
        guard let loc = locate(entryID, itemID), store.journal[loc.0].items[loc.1].status == .proposed else { return }
        store.journal[loc.0].items[loc.1].status = .dismissed
    }

    @discardableResult
    func undo(entryID: UUID, itemID: UUID) -> Bool {
        guard let loc = locate(entryID, itemID) else { return false }
        let item = store.journal[loc.0].items[loc.1]
        guard item.canUndo else { return false }
        revert(item.undo)
        store.journal[loc.0].items[loc.1].status = .undone
        return true
    }

    /// Décocher une habitude (écran Hygiène) : retire le log du jour et décoche la tâche du Hub liée.
    func unsetHygiene(_ h: HygieneHabit) {
        store.hygieneLog.removeAll { $0.habit == h.rawValue && cal.isDateInToday($0.date) }
        for i in store.tasks.indices where store.tasks[i].habits.contains(h) {
            store.tasks[i].done = false
            store.tasks[i].doneAt = nil
        }
    }

    // MARK: Validation (types, bornes, dates)
    func validate(_ a: AppAction) -> String? {
        let startOfToday = cal.startOfDay(for: .now)
        switch a {
        case .expense(let amount, _, _), .income(let amount, _):
            if !(amount > 0 && amount <= 100_000) { return "montant invalide (\(amount))" }
        case .meal(let items):
            if items.isEmpty { return "aucun aliment" }
            if items.count > 15 { return "trop d'aliments d'un coup" }
            for i in items {
                if i.name.trimmingCharacters(in: .whitespaces).isEmpty { return "aliment sans nom" }
                if !(1...3000).contains(i.grams) { return "quantité invalide pour \(i.name)" }
                if !(0...5000).contains(i.kcal) || !(0...300).contains(i.protein) { return "valeurs nutritionnelles invalides pour \(i.name)" }
            }
        case .water(let ml):
            if !(50...5000).contains(ml) { return "quantité d'eau invalide" }
        case .hygiene(let habits):
            if habits.isEmpty { return "aucune habitude reconnue" }
        case .completeTask(let r), .startTask(let r), .removeTask(let r), .completeHomework(let r),
             .tutorSession(let r), .tutorPaid(let r), .completeChallenge(let r):
            if r.trimmingCharacters(in: .whitespaces).isEmpty { return "référence vide" }
        case .addTask(let title, let start, let duration, _):
            if title.trimmingCharacters(in: .whitespaces).isEmpty { return "titre vide" }
            if !(0..<1440).contains(start) { return "heure invalide" }
            if !(5...600).contains(duration) { return "durée invalide (5 à 600 min)" }
        case .replanDay(let slots):
            if slots.isEmpty { return "planning vide" }
            if slots.contains(where: { !(0..<1500).contains($0.start) }) { return "heure invalide dans le planning" }
        case .switchActivity(let title, let minutes):
            if title.trimmingCharacters(in: .whitespaces).isEmpty { return "activité vide" }
            if !(5...480).contains(minutes) { return "durée invalide (5 à 480 min)" }
        case .workoutSet(let exercise, let weight, let reps, let effort):
            if exercise.trimmingCharacters(in: .whitespaces).isEmpty { return "exercice vide" }
            if !(0...400).contains(weight) { return "charge invalide" }
            if !(1...100).contains(reps) { return "nombre de répétitions invalide" }
            if let e = effort, !(1...3).contains(e) { return "effort invalide" }
        case .health(_, let text), .note(let text):
            if text.trimmingCharacters(in: .whitespaces).isEmpty { return "texte vide" }
        case .reminder(let title, let date, let rule, _):
            if title.trimmingCharacters(in: .whitespaces).isEmpty { return "titre du rappel vide" }
            if !["none", "daily", "weekly", "monthly"].contains(rule) { return "répétition inconnue" }
            if rule == "none" && date < Date().addingTimeInterval(-60) { return "la date du rappel est déjà passée" }
            if date > Date().addingTimeInterval(2 * 365 * 86400) { return "date trop lointaine" }
        case .exam(let subject, let date, _):
            if subject.trimmingCharacters(in: .whitespaces).isEmpty { return "matière vide" }
            if date < startOfToday { return "la date du contrôle est passée" }
            if date > Date().addingTimeInterval(365 * 86400) { return "date trop lointaine" }
        case .homework(let subject, let title, let due):
            if subject.trimmingCharacters(in: .whitespaces).isEmpty || title.trimmingCharacters(in: .whitespaces).isEmpty { return "devoir incomplet" }
            if due < startOfToday { return "la date de rendu est passée" }
        case .setLockdown(let minutes):
            if let m = minutes, !(5...480).contains(m) { return "durée de Lockdown invalide" }
        case .add(let r), .update(let r):
            if let why = validateRecord(r) { return why }
        case .undoLast, .navigate, .delete, .reopenHomework, .reopenChallenge, .finishWorkout:
            break
        }
        return nil
    }

    // MARK: Exécution
    private func run(_ a: AppAction) -> ActionResult {
        if let why = validate(a) { return .rejected("Refusé : \(why)") }
        switch a {
        case .expense(let amount, let category, let note):
            return expense(amount: amount, category: category, note: note)

        case .income(let amount, let note):
            let t = Txn(date: .now, amount: amount, category: "Revenu", note: note.isEmpty ? "Argent reçu" : note)
            store.txns.append(t)
            return ActionResult(status: .applied, summary: "Revenu \(Fmt.signedMoney(amount, store.currency)) → Finances (solde \(Fmt.money(store.balance, store.currency)))",
                                destination: .finance, undo: [.removeTxn(t.id)])

        case .meal(let items):
            return meal(items)

        case .water(let ml):
            let n = max(1, Int((Double(ml) / 250).rounded()))
            var ids: [UUID] = []
            for _ in 0..<n {
                let e = HealthEntry(date: .now, kind: "Eau", text: "250 ml")
                store.healthLog.append(e); ids.append(e.id)
            }
            return ActionResult(status: .applied, summary: "Eau +\(n * 250) ml (total \(store.waterToday) ml) → Santé",
                                destination: .health, undo: [.removeHealth(ids)])

        case .hygiene(let habits):
            return hygiene(habits)

        case .completeTask(let ref):
            return completeTask(ref)

        case .startTask(let ref):
            guard let i = Planner.match(ref, in: store.tasks, now: now, includeDone: false) else {
                return .rejected("Je ne trouve pas la tâche « \(ref) » dans le planning du jour.")
            }
            let t = store.tasks[i]
            if t.isFixed { return .rejected("‹\(t.title)› a un horaire fixe, elle ne se déplace pas.") }
            if t.startedAt != nil && t.start <= now { return ActionResult(status: .duplicate, summary: "‹\(t.title)› est déjà en cours", destination: .hub) }
            let before = timings()
            store.tasks[i].start = now
            store.tasks[i].startedAt = now
            let dropped = reflow(pinned: [t.id])
            return ActionResult(status: .applied, summary: "‹\(t.title)› démarrée à \(timeString(now))\(nextLine(after: t.id))\(droppedLine(dropped))",
                                destination: .hub, undo: [UndoOp.restoreTimings(before)] + reinsert(dropped))

        case .addTask(let title, let start, let duration, let kind):
            let before = timings()
            let t = TaskItem(title: title, icon: Planner.icon(for: kind), start: start, duration: duration, kind: kind)
            store.tasks.append(t)
            let dropped = reflow(pinned: [t.id])
            return ActionResult(status: .applied, summary: "Tâche ajoutée : ‹\(title)› à \(timeString(start)) (\(duration) min)\(droppedLine(dropped))",
                                destination: .hub, undo: [UndoOp.removeTask(t.id), UndoOp.restoreTimings(before)] + reinsert(dropped))

        case .removeTask(let ref):
            guard let i = Planner.match(ref, in: store.tasks, now: now, includeDone: false) else {
                return .rejected("Je ne trouve pas la tâche « \(ref) ».")
            }
            let t = store.tasks.remove(at: i)
            return ActionResult(status: .applied, summary: "Tâche retirée : ‹\(t.title)›", destination: .hub, undo: [.insertTask(t)])

        case .replanDay(let slots):
            let before = timings()
            let r = Planner.replan(store.tasks, slots: slots, now: now, limit: store.planLimit)
            guard !r.moved.isEmpty else { return .rejected("Aucune tâche du planning ne correspond à la proposition.") }
            store.tasks = r.tasks
            return ActionResult(status: .applied, summary: "Planning réorganisé : " + timesLine(r.moved, in: r.tasks)
                                    + (r.unknown.isEmpty ? "" : " (introuvable : \(r.unknown.joined(separator: ", ")))") + droppedLine(r.dropped),
                                destination: .hub, undo: [UndoOp.restoreTimings(before)] + reinsert(r.dropped))

        case .switchActivity(let title, let minutes):
            let before = timings()
            // La tâche en cours est interrompue : elle reprendra après l'activité.
            for i in store.tasks.indices where !store.tasks[i].done && !store.tasks[i].isFixed { store.tasks[i].startedAt = nil }
            let t = TaskItem(title: title, icon: "bolt.fill", start: now, duration: minutes, kind: .other, done: true, startedAt: now, doneAt: now + minutes)
            store.tasks.append(t)
            let r = Planner.reflow(store.tasks, from: now + minutes, limit: store.planLimit, clock: now)
            store.tasks = r.tasks
            let movedIDs = r.tasks.filter { !$0.done && !$0.isFixed && $0.start >= now + minutes }.prefix(3).map(\.id)
            return ActionResult(status: .applied, summary: "Je fais autre chose : \(title) (\(minutes) min) → planning décalé : "
                                    + timesLine(Array(movedIDs), in: store.tasks) + droppedLine(r.dropped),
                                destination: .hub, undo: [UndoOp.removeTask(t.id), UndoOp.restoreTimings(before)] + reinsert(r.dropped))

        case .workoutSet(let exercise, let weight, let reps, let effort):
            let name = canonicalExercise(exercise)
            let s = SetRecord(date: .now, exercise: name, weight: weight, reps: reps, effort: effort)
            store.sets.append(s)
            let count = store.todaySets(name).count
            return ActionResult(status: .applied, summary: "Série : \(name) \(fmtKg(weight)) kg × \(reps) (série n°\(count) aujourd'hui) → Muscu",
                                destination: .muscu, undo: [.removeSet(s.id)])

        case .health(let kind, let text):
            let k = ["Sommeil", "Symptôme", "Médicament", "Énergie", "Autre"].contains(kind) ? kind : "Autre"
            let e = HealthEntry(date: .now, kind: k, text: text)
            store.healthLog.append(e)
            return ActionResult(status: .applied, summary: "Santé (\(k)) : \(text) → Santé", destination: .health, undo: [.removeHealth([e.id])])

        case .note(let text):
            let n = NoteItem(date: .now, text: text)
            store.notes.insert(n, at: 0)
            return ActionResult(status: .applied, summary: "Note ajoutée : « \(String(text.prefix(60))) » → Notes", destination: .notes, undo: [.removeNote(n.id)])

        case .reminder(let title, let date, let rule, let urgent):
            if store.reminders.contains(where: { Planner.normalize($0.title) == Planner.normalize(title) && $0.repeatRule == rule && abs($0.date.timeIntervalSince(date)) < 60 }) {
                return ActionResult(status: .duplicate, summary: "Ce rappel existe déjà", destination: .reminders)
            }
            let r = UserReminder(title: title, date: date, repeatRule: rule, urgent: urgent)
            store.reminders.append(r)
            NotificationManager.shared.scheduleReminder(r, name: store.displayName)
            return ActionResult(status: .applied, summary: "Rappel « \(title) » — \(Fmt.reminderRule(date, rule)) → Rappels (notification programmée)",
                                destination: .reminders, undo: [.removeReminder(r.id)])

        case .exam(let subject, let date, let topic):
            if store.exams.contains(where: { Planner.normalize($0.subject) == Planner.normalize(subject) && cal.isDate($0.date, inSameDayAs: date) }) {
                return ActionResult(status: .duplicate, summary: "Contrôle de \(subject) déjà enregistré ce jour-là", destination: .school)
            }
            let e = ExamItem(subject: subject, date: date, topic: topic)
            store.exams.append(e)
            var undo: [UndoOp] = [.removeExam(e.id)]
            var extra = ""
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: date)).day ?? 99
            if (0...3).contains(days), !store.tasks.contains(where: { $0.linkID == e.id }) {
                let before = timings()
                let t = TaskItem(title: "Réviser \(subject) – contrôle \(Planner.examLabel(days))", icon: "text.book.closed.fill",
                                 start: max(now + 10, 17 * 60), duration: 45, kind: .study, linkID: e.id)
                store.tasks.append(t)
                let dropped = reflow()
                if store.tasks.contains(where: { $0.id == t.id }) {
                    undo += [UndoOp.removeTask(t.id), UndoOp.restoreTimings(before)] + reinsert(dropped)
                    extra = " · révision ajoutée au planning"
                }
            }
            return ActionResult(status: .applied, summary: "Contrôle de \(subject) le \(Fmt.dayMonth(date))\(topic.isEmpty ? "" : " (\(topic))") → Études\(extra)",
                                destination: .school, undo: undo)

        case .homework(let subject, let title, let due):
            if store.homework.contains(where: { Planner.normalize($0.subject) == Planner.normalize(subject) && Planner.normalize($0.title) == Planner.normalize(title) && cal.isDate($0.due, inSameDayAs: due) }) {
                return ActionResult(status: .duplicate, summary: "Ce devoir est déjà noté", destination: .study)
            }
            let h = Homework(subject: subject, title: title, due: due)
            store.homework.append(h)
            return ActionResult(status: .applied, summary: "Devoir de \(subject) : \(title) pour le \(Fmt.dayMonth(due)) → Études",
                                destination: .study, undo: [.removeHomework(h.id)])

        case .completeHomework(let ref):
            let r = Planner.normalize(ref)
            let byID = UUID(uuidString: ref).flatMap { u in store.homework.firstIndex { $0.id == u && !$0.done } }
            guard let i = byID ?? store.homework.firstIndex(where: { !$0.done && (r.contains(Planner.normalize($0.subject)) || Planner.normalize($0.title).contains(r) || Planner.normalize($0.subject).contains(r)) }) else {
                return .rejected("Aucun devoir en attente ne correspond à « \(ref) ».")
            }
            store.homework[i].done = true
            let h = store.homework[i]
            return ActionResult(status: .applied, summary: "Devoir rendu : \(h.subject) – \(h.title) → Études", destination: .study, undo: [.setHomeworkDone(h.id, false)])

        case .tutorSession(let ref):
            guard let tutor = matchTutor(ref) else { return .rejected("Je ne trouve pas de prof correspondant à « \(ref) ».") }
            if store.tutorSessions.contains(where: { $0.tutorID == tutor.id && cal.isDateInToday($0.date) }) {
                return ActionResult(status: .duplicate, summary: "Séance avec \(tutor.name) déjà notée aujourd'hui", destination: .tutors)
            }
            let s = TutorSession(tutorID: tutor.id, date: .now)
            store.tutorSessions.append(s)
            var undo: [UndoOp] = [.removeTutorSession(s.id)]
            if let i = store.tasks.firstIndex(where: { $0.kind == .tutor && $0.linkID == tutor.id && !$0.done }) {
                store.tasks[i].done = true; store.tasks[i].doneAt = now
                undo.append(.setTaskDone(store.tasks[i].id, false))
            }
            let count = monthSessions(tutor).count
            return ActionResult(status: .applied, summary: "Séance faite ✅ avec \(tutor.name) (\(count)/\(tutor.sessionsPerMonth) ce mois) → Cours particuliers",
                                destination: .tutors, undo: undo)

        case .tutorPaid(let ref):
            guard let tutor = matchTutor(ref) else { return .rejected("Je ne trouve pas de prof correspondant à « \(ref) ».") }
            let unpaid = monthSessions(tutor).filter { !$0.paid }
            guard !unpaid.isEmpty else { return .rejected("Aucune séance non payée ce mois-ci pour \(tutor.name).") }
            let amount = Double(unpaid.count) * tutor.price
            let t = Txn(date: .now, amount: -amount, category: "Études", note: "Cours \(tutor.subject) – \(tutor.name)")
            store.txns.append(t)
            let ids = Set(unpaid.map(\.id))
            for i in store.tutorSessions.indices where ids.contains(store.tutorSessions[i].id) { store.tutorSessions[i].paid = true }
            return ActionResult(status: .applied, summary: "Khallast 💸 \(Fmt.signedMoney(-amount, store.currency)) → \(tutor.name) (\(unpaid.count) séance(s)) → Finances",
                                destination: .tutors, undo: [.removeTxn(t.id), .setTutorSessionsPaid(Array(ids), false)])

        case .completeChallenge(let ref):
            guard let c = matchChallenge(ref), let i = store.challenges.firstIndex(where: { $0.id == c.id }) else {
                return .rejected("Aucun défi du jour ne correspond à « (ref) ».")
            }
            store.challenges[i].done = true
            return ActionResult(status: .applied, summary: "Défi réussi 🔥 : (c.text) → Micro-défis", destination: .challenges, undo: [.setChallengeDone(c.id, false)])

        case .undoLast:
            for e in store.journal.indices.reversed() {
                for i in store.journal[e].items.indices.reversed() where store.journal[e].items[i].canUndo {
                    let it = store.journal[e].items[i]
                    revert(it.undo)
                    store.journal[e].items[i].status = .undone
                    return ActionResult(status: .applied, summary: "Annulé : \(it.summary)", destination: it.destination)
                }
            }
            return .rejected("Rien à annuler.")

        case .navigate(let dest):
            return ActionResult(status: .applied, summary: "Ouverture : \(dest.title)", destination: dest)

        case .add(let r):
            if store.record(r.ref) != nil { return ActionResult(status: .duplicate, summary: "Déjà enregistré : \(r.label)", destination: r.destination) }
            store.upsert(r)
            afterUpsert(r)
            var undo: [UndoOp] = [.remove(r.ref)]
            var extra = ""
            if case .tutor(let t) = r, t.weekday == cal.component(.weekday, from: .now) {
                let before = timings()
                let task = TaskItem(title: "Cours particulier : \(t.subject) (\(t.name))", icon: "person.2.fill",
                                    start: t.hour * 60 + t.minute, duration: 60, kind: .tutor, linkID: t.id)
                store.tasks.append(task)
                let dropped = reflow()
                undo += [UndoOp.removeTask(task.id), UndoOp.restoreTimings(before)] + reinsert(dropped)
                extra = " · ajouté au planning d'aujourd'hui"
            }
            return ActionResult(status: .applied, summary: "Ajouté : \(r.label)\(extra)", destination: r.destination, undo: undo)

        case .update(let r):
            guard let old = store.record(r.ref) else { return .rejected("Élément introuvable : \(r.label)") }
            if old == r { return ActionResult(status: .duplicate, summary: "Aucun changement", destination: r.destination) }
            store.upsert(r)
            afterUpsert(r)
            return ActionResult(status: .applied, summary: "Modifié : \(r.label)", destination: r.destination, undo: [.upsert(old)])

        case .delete(let ref):
            guard let old = store.removeRecord(ref) else { return .rejected("Élément déjà supprimé.") }
            afterRemove(old)
            return ActionResult(status: .applied, summary: "Supprimé : \(old.label)", destination: ref.destination, undo: [.upsert(old)])

        case .reopenHomework(let id):
            guard let i = store.homework.firstIndex(where: { $0.id == id }), store.homework[i].done else {
                return ActionResult(status: .duplicate, summary: "Devoir déjà à faire", destination: .study)
            }
            store.homework[i].done = false
            return ActionResult(status: .applied, summary: "Devoir à refaire : \(store.homework[i].subject) – \(store.homework[i].title)",
                                destination: .study, undo: [.setHomeworkDone(id, true)])

        case .reopenChallenge(let id):
            guard let i = store.challenges.firstIndex(where: { $0.id == id }), store.challenges[i].done else {
                return ActionResult(status: .duplicate, summary: "Défi déjà à faire", destination: .challenges)
            }
            store.challenges[i].done = false
            return ActionResult(status: .applied, summary: "Défi décoché : \(store.challenges[i].text)", destination: .challenges,
                                undo: [.setChallengeDone(id, true)])

        case .finishWorkout:
            if let t = store.tasks.first(where: { $0.kind == .workout && !$0.done }) { return completeTask(t.id.uuidString) }
            let old = store.workoutCursor
            store.workoutCursor = (old + 1) % Program.days.count
            return ActionResult(status: .applied, summary: "Séance \(Program.days[old].code) terminée · prochaine : \(Program.days[store.workoutCursor].code) \(Program.days[store.workoutCursor].name)",
                                destination: .muscu, undo: [.setWorkoutCursor(old)])

        case .setLockdown(let minutes):
            if let m = minutes {
                store.lockdownEnd = Date().addingTimeInterval(Double(m) * 60)
                store.lockdownActive = true
                return ActionResult(status: .applied, summary: "Lockdown activé pour \(m) min", destination: .study)
            }
            store.lockdownActive = false
            store.lockdownEnd = nil
            return ActionResult(status: .applied, summary: "Lockdown terminé", destination: .study)
        }
    }

    // MARK: Données génériques (Lot 2)
    private func validateRecord(_ r: Record) -> String? {
        switch r {
        case .txn(let x): return x.amount == 0 || abs(x.amount) > 100_000 ? "montant invalide" : nil
        case .food(let x): return x.grams <= 0 ? "quantité invalide" : nil
        case .homework(let x): return x.subject.isEmpty ? "matière vide" : nil
        case .exam(let x): return x.subject.isEmpty ? "matière vide" : nil
        case .reminder(let x): return x.title.trimmingCharacters(in: .whitespaces).isEmpty ? "titre vide" : nil
        case .tutor(let x):
            if x.name.trimmingCharacters(in: .whitespaces).isEmpty { return "nom du prof vide" }
            if !(1...7).contains(x.weekday) || !(0...23).contains(x.hour) || !(0...59).contains(x.minute) { return "horaire invalide" }
            return x.price < 0 || x.price > 10_000 ? "prix invalide" : nil
        case .timetable(let x): return x.end <= x.start || !(1...7).contains(x.weekday) ? "horaire de cours invalide" : nil
        case .note(let x): return x.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "note vide" : nil
        case .health(let x): return x.text.isEmpty ? "texte vide" : nil
        case .project(let x): return x.title.trimmingCharacters(in: .whitespaces).isEmpty ? "nom du projet vide" : nil
        case .clothing(let x): return x.name.trimmingCharacters(in: .whitespaces).isEmpty ? "nom de l'habit vide" : nil
        case .challenge(let x): return x.text.isEmpty ? "défi vide" : nil
        case .capsule(let x): return x.unlock <= Date() ? "la date d'ouverture doit être dans le futur" : nil
        case .runRecord(let x): return x.distance < 0 ? "distance invalide" : nil
        case .lesson, .customFood, .workoutSet, .review, .dish, .tutorSession: return nil
        }
    }

    /// Effets de bord d'un ajout / d'une modification (notifications…).
    private func afterUpsert(_ r: Record) {
        switch r {
        case .reminder(let x):
            NotificationManager.shared.cancelReminder(x.id)
            NotificationManager.shared.scheduleReminder(x, name: store.displayName)
        case .tutor(let x):
            NotificationManager.shared.cancelTutor(x)
            NotificationManager.shared.scheduleTutor(x)
        case .capsule(let x):
            NotificationManager.shared.schedule(id: "capsule-\(x.id)", title: "⏳ Ta capsule temporelle s'ouvre",
                                                body: "Un message de ton passé t'attend.", date: x.unlock)
        default:
            break
        }
    }

    private func afterRemove(_ r: Record) {
        switch r {
        case .reminder(let x): NotificationManager.shared.cancelReminder(x.id)
        case .tutor(let x): NotificationManager.shared.cancelTutor(x)
        case .capsule(let x): NotificationManager.shared.cancel(id: "capsule-\(x.id)")
        default: break
        }
    }

    // MARK: Actions détaillées
    private func expense(amount: Double, category: String, note: String) -> ActionResult {
        let cat = normalizeCategory(category)
        let t = Txn(date: .now, amount: -amount, category: cat, note: note)
        store.txns.append(t)
        var undo: [UndoOp] = [.removeTxn(t.id)]
        var extra = ""
        // Catégorie « Études » : le paiement alimente le suivi du prof particulier.
        if cat == "Études", let tutor = matchTutor(note) {
            var remaining = amount + 0.001
            var paid: [UUID] = []
            for s in monthSessions(tutor).filter({ !$0.paid }).sorted(by: { $0.date < $1.date }) where remaining >= tutor.price {
                if let i = store.tutorSessions.firstIndex(where: { $0.id == s.id }) {
                    store.tutorSessions[i].paid = true
                    paid.append(s.id)
                    remaining -= tutor.price
                }
            }
            if !paid.isEmpty {
                undo.append(.setTutorSessionsPaid(paid, false))
                extra = " · \(paid.count) séance(s) de \(tutor.name) marquée(s) payée(s)"
            }
        }
        return ActionResult(status: .applied, summary: "Dépense \(Fmt.signedMoney(-amount, store.currency)) (\(cat)) → Finances\(extra)",
                            destination: .finance, undo: undo)
    }

    private func meal(_ items: [MealLine]) -> ActionResult {
        var ids: [UUID] = []
        var cards: [String] = []
        for it in items {
            let f = FoodEntry(date: .now, name: it.name, grams: it.grams, kcal: it.kcal, protein: it.protein)
            store.foods.append(f)
            ids.append(f.id)
            if let c = store.ensureCard(name: it.name, grams: it.grams, kcal: it.kcal, protein: it.protein) { cards.append(c) }
        }
        var undo: [UndoOp] = [.removeFoods(ids)]
        if !cards.isEmpty { undo.append(.removeCustomFoods(cards)) }
        var extra = cards.isEmpty ? "" : " · \(cards.count) nouvelle(s) carte(s)"
        // Coche la tâche « repas » la plus proche de l'heure actuelle.
        let candidates = store.tasks.indices.filter {
            let t = store.tasks[$0]
            return t.kind == .meal && !t.done && now >= t.start - 90 && now <= t.end + 120
        }
        if let j = candidates.min(by: { abs(store.tasks[$0].start - now) < abs(store.tasks[$1].start - now) }) {
            store.tasks[j].done = true
            store.tasks[j].doneAt = now
            undo.append(.setTaskDone(store.tasks[j].id, false))
            extra += " · tâche ‹\(store.tasks[j].title)› cochée"
        }
        let kcal = Int(items.reduce(0) { $0 + $1.kcal }), prot = Int(items.reduce(0) { $0 + $1.protein })
        return ActionResult(status: .applied,
                            summary: "Repas : \(items.map(\.name).joined(separator: ", ")) ≈ \(kcal) kcal · \(prot) g prot. → Nutrition (\(Int(store.kcalToday))/\(Int(store.calorieGoal)) kcal)\(extra)",
                            destination: .nutrition, undo: undo)
    }

    private func hygiene(_ habits: [HygieneHabit]) -> ActionResult {
        let fresh = habits.filter { !store.hygieneDone($0) }
        let label = habits.map(\.shortTitle).joined(separator: ", ")
        guard !fresh.isEmpty else {
            // Habitude déjà faite : on s'assure quand même que la tâche du Hub est cochée (synchronisation).
            let fixed = checkHygieneTasks()
            return ActionResult(status: fixed.isEmpty ? .duplicate : .applied,
                                summary: fixed.isEmpty ? "\(label) : déjà validé aujourd'hui" : "Tâche ‹\(fixed.map { $0.1 }.joined(separator: ", "))› cochée",
                                destination: .hygiene, undo: fixed.map { UndoOp.setTaskDone($0.0, false) })
        }
        var ids: [UUID] = []
        for h in fresh {
            let l = HygieneLog(date: .now, habit: h.rawValue)
            store.hygieneLog.append(l); ids.append(l.id)
        }
        let fixed = checkHygieneTasks()
        var undo: [UndoOp] = [.removeHygiene(ids)]
        undo += fixed.map { UndoOp.setTaskDone($0.0, false) }
        let tasksLine = fixed.isEmpty ? "" : " · tâche ‹\(fixed.map { $0.1 }.joined(separator: ", "))› cochée"
        return ActionResult(status: .applied, summary: "Hygiène : \(fresh.map(\.shortTitle).joined(separator: ", ")) ✓ (\(store.hygieneDoneCount)/6)\(tasksLine)",
                            destination: .hygiene, undo: undo)
    }

    /// Coche les tâches d'hygiène dont toutes les habitudes sont faites. Renvoie (id, titre) des tâches cochées.
    private func checkHygieneTasks() -> [(UUID, String)] {
        var out: [(UUID, String)] = []
        for i in store.tasks.indices {
            let t = store.tasks[i]
            guard !t.done, !t.habits.isEmpty, t.habits.allSatisfy({ store.hygieneDone($0) }) else { continue }
            store.tasks[i].done = true
            store.tasks[i].doneAt = now
            out.append((t.id, t.title))
        }
        return out
    }

    private func completeTask(_ ref: String) -> ActionResult {
        guard let i = Planner.match(ref, in: store.tasks, now: now, includeDone: true) else {
            return .rejected("Je ne trouve pas la tâche « \(ref) » dans le planning du jour.")
        }
        let t = store.tasks[i]
        if t.done { return ActionResult(status: .duplicate, summary: "‹\(t.title)› était déjà terminée", destination: .hub) }
        let before = timings()
        store.tasks[i].done = true
        store.tasks[i].doneAt = now
        var undo: [UndoOp] = [.restoreTimings(before), .setTaskDone(t.id, false)]
        var extra = ""

        // Effets croisés
        if !t.habits.isEmpty {
            var ids: [UUID] = []
            for h in t.habits where !store.hygieneDone(h) {
                let l = HygieneLog(date: .now, habit: h.rawValue)
                store.hygieneLog.append(l); ids.append(l.id)
            }
            if !ids.isEmpty { undo.append(.removeHygiene(ids)); extra += " · hygiène \(store.hygieneDoneCount)/6" }
        }
        if t.kind == .workout {
            undo.append(.setWorkoutCursor(store.workoutCursor))
            store.workoutCursor = (store.workoutCursor + 1) % Program.days.count
            extra += " · prochaine séance : \(Program.days[store.workoutCursor].code)"
        }
        if t.kind == .tutor, let tid = t.linkID, store.tutors.contains(where: { $0.id == tid }),
           !store.tutorSessions.contains(where: { $0.tutorID == tid && cal.isDateInToday($0.date) }) {
            let s = TutorSession(tutorID: tid, date: .now)
            store.tutorSessions.append(s)
            undo.append(.removeTutorSession(s.id))
            extra += " · séance comptée"
        }

        // Fin en retard : la suite glisse. Fin en avance : la suite reste, le Hub propose « Commencer maintenant ».
        let dropped = reflow()
        undo += reinsert(dropped)
        return ActionResult(status: .applied, summary: "Tâche ‹\(t.title)› terminée\(extra)\(nextLine(after: t.id))\(droppedLine(dropped))",
                            destination: .hub, undo: undo)
    }

    // MARK: Annulation
    private func revert(_ ops: [UndoOp]) {
        for op in ops.reversed() {
            switch op {
            case .removeTxn(let id): store.txns.removeAll { $0.id == id }
            case .removeFoods(let ids): store.foods.removeAll { ids.contains($0.id) }
            case .removeCustomFoods(let ids): store.customFoods.removeAll { ids.contains($0.id) }
            case .setTaskDone(let id, let value):
                if let i = store.tasks.firstIndex(where: { $0.id == id }) {
                    store.tasks[i].done = value
                    if !value { store.tasks[i].doneAt = nil }
                }
            case .restoreTimings(let list):
                for tm in list {
                    if let i = store.tasks.firstIndex(where: { $0.id == tm.id }) {
                        store.tasks[i].start = tm.start
                        store.tasks[i].duration = tm.duration
                        store.tasks[i].startedAt = tm.startedAt
                    }
                }
            case .removeTask(let id): store.tasks.removeAll { $0.id == id }
            case .insertTask(let t): if !store.tasks.contains(where: { $0.id == t.id }) { store.tasks.append(t) }
            case .removeHygiene(let ids): store.hygieneLog.removeAll { ids.contains($0.id) }
            case .removeHealth(let ids): store.healthLog.removeAll { ids.contains($0.id) }
            case .removeSet(let id): store.sets.removeAll { $0.id == id }
            case .removeNote(let id): store.notes.removeAll { $0.id == id }
            case .removeReminder(let id):
                store.reminders.removeAll { $0.id == id }
                NotificationManager.shared.cancelReminder(id)
            case .removeExam(let id): store.exams.removeAll { $0.id == id }
            case .removeHomework(let id): store.homework.removeAll { $0.id == id }
            case .setHomeworkDone(let id, let value):
                if let i = store.homework.firstIndex(where: { $0.id == id }) { store.homework[i].done = value }
            case .removeTutorSession(let id): store.tutorSessions.removeAll { $0.id == id }
            case .setTutorSessionsPaid(let ids, let value):
                for i in store.tutorSessions.indices where ids.contains(store.tutorSessions[i].id) { store.tutorSessions[i].paid = value }
            case .setChallengeDone(let id, let value):
                if let i = store.challenges.firstIndex(where: { $0.id == id }) { store.challenges[i].done = value }
            case .setWorkoutCursor(let v): store.workoutCursor = v
            case .remove(let ref):
                if let old = store.removeRecord(ref) { afterRemove(old) }
            case .upsert(let r):
                store.upsert(r)
                afterUpsert(r)
            }
        }
        store.tasks.sort { $0.start < $1.start }
    }

    // MARK: Aperçu d'une proposition (même calcul que l'exécution réelle)
    func preview(_ a: AppAction) -> String {
        switch a {
        case .replanDay(let slots):
            let r = Planner.replan(store.tasks, slots: slots, now: now, limit: store.planLimit)
            if r.moved.isEmpty { return "Proposition de planning (aucune tâche reconnue)" }
            return "Planning proposé : " + timesLine(r.moved, in: r.tasks) + droppedLine(r.dropped)
        case .reminder(let title, let date, let rule, _):
            return "Rappel proposé : « \(title) » — \(Fmt.reminderRule(date, rule))"
        case .addTask(let title, let start, let duration, _):
            return "Ajouter ‹\(title)› à \(timeString(start)) (\(duration) min)"
        case .removeTask(let ref):
            return "Retirer ‹\(ref)› du planning"
        case .switchActivity(let title, let minutes):
            return "Faire « \(title) » pendant \(minutes) min et décaler la suite"
        case .exam(let subject, let date, _):
            return "Ajouter le contrôle de \(subject) le \(Fmt.dayMonth(date))"
        case .homework(let subject, let title, let due):
            return "Ajouter le devoir \(subject) – \(title) pour le \(Fmt.dayMonth(due))"
        default:
            return "Action proposée"
        }
    }

    private func destination(of a: AppAction) -> AppDestination? {
        switch a {
        case .expense, .income, .tutorPaid: return .finance
        case .meal: return .nutrition
        case .water, .health: return .health
        case .hygiene: return .hygiene
        case .completeTask, .startTask, .addTask, .removeTask, .replanDay, .switchActivity: return .hub
        case .workoutSet: return .muscu
        case .note: return .notes
        case .reminder: return .reminders
        case .exam: return .school
        case .homework, .completeHomework: return .study
        case .tutorSession: return .tutors
        case .completeChallenge: return .challenges
        case .undoLast: return nil
        case .navigate(let d): return d
        case .add(let r), .update(let r): return r.destination
        case .delete(let ref): return ref.destination
        case .reopenHomework, .setLockdown: return .study
        case .reopenChallenge: return .challenges
        case .finishWorkout: return .muscu
        }
    }

    // MARK: Utilitaires
    private func record(_ e: JournalEntry) {
        store.journal.append(e)
        store.trimJournal()
    }

    private func makeItem(_ a: AppAction, _ r: ActionResult) -> JournalItem {
        JournalItem(action: a, status: r.status, summary: r.summary, destination: r.destination ?? destination(of: a), undo: r.undo, fingerprint: a.fingerprint)
    }

    private func locate(_ entryID: UUID, _ itemID: UUID) -> (Int, Int)? {
        guard let e = store.journal.firstIndex(where: { $0.id == entryID }),
              let i = store.journal[e].items.firstIndex(where: { $0.id == itemID }) else { return nil }
        return (e, i)
    }

    private func recentlyApplied(_ fp: String, within seconds: TimeInterval) -> Bool {
        let since = Date().addingTimeInterval(-seconds)
        return store.journal.suffix(30).contains { e in
            e.date >= since && e.source == .nexus && e.items.contains { $0.fingerprint == fp && $0.status == .applied }
        }
    }

    private func timings() -> [TaskTiming] {
        store.tasks.map { TaskTiming(id: $0.id, start: $0.start, duration: $0.duration, startedAt: $0.startedAt) }
    }

    @discardableResult
    private func reflow(pinned: Set<UUID> = []) -> [TaskItem] {
        let r = Planner.reflow(store.tasks, from: now, limit: store.planLimit, pinned: pinned)
        store.tasks = r.tasks
        return r.dropped
    }

    private func nextLine(after id: UUID) -> String {
        guard let n = store.pending.first(where: { $0.id != id }) else { return " · planning terminé 🎉" }
        return " · ensuite ‹\(n.title)› à \(timeString(n.start))"
    }

    private func droppedLine(_ dropped: [TaskItem]) -> String {
        dropped.isEmpty ? "" : " · ne rentre plus aujourd'hui : \(dropped.map(\.title).joined(separator: ", "))"
    }

    private func timesLine(_ ids: [UUID], in tasks: [TaskItem]) -> String {
        let list = tasks.filter { ids.contains($0.id) }.sorted { $0.start < $1.start }
        return list.isEmpty ? "rien à décaler" : list.map { "\($0.title) \(timeString($0.start))" }.joined(separator: ", ")
    }

    private func normalizeCategory(_ c: String) -> String {
        let n = Planner.normalize(c)
        if let exact = Finance.categoryNames.first(where: { Planner.normalize($0) == n }) { return exact }
        let map: [String: String] = ["snack": "Snacks", "goute": "Snacks", "bonbon": "Snacks", "food": "Nutrition", "manger": "Nutrition",
                                     "bus": "Transport", "taxi": "Transport", "louage": "Transport", "fourniture": "École", "cahier": "École",
                                     "cours": "Études", "prof": "Études", "salle": "Sport", "gym": "Sport", "jeu": "Loisirs", "cinema": "Loisirs"]
        for (k, v) in map where n.contains(k) { return v }
        return "Autre"
    }

    private func matchTutor(_ ref: String) -> Tutor? {
        if let u = UUID(uuidString: ref) { return store.tutors.first { $0.id == u } }
        let r = Planner.normalize(ref)
        if !r.isEmpty, let t = store.tutors.first(where: {
            let name = Planner.normalize($0.name), subject = Planner.normalize($0.subject)
            return r.contains(name) || r.contains(subject) || name.contains(r) || subject.contains(r)
        }) { return t }
        return store.tutors.count == 1 ? store.tutors.first : nil
    }

    private func matchChallenge(_ ref: String) -> Challenge? {
        let r = Planner.normalize(ref)
        if let u = UUID(uuidString: ref) { return store.challenges.first { $0.id == u && !$0.done } }
        let open = store.challengesToday.filter { !$0.done }
        if let c = open.first(where: { Planner.normalize($0.text).contains(r) || r.contains(Planner.normalize($0.text)) }) { return c }
        for c in open {
            let words = Planner.normalize(c.text).split(separator: " ").map(String.init).filter { $0.count > 3 }
            if words.contains(where: { r.contains($0) }) { return c }
        }
        return open.count == 1 ? open.first : nil
    }

    private func reinsert(_ dropped: [TaskItem]) -> [UndoOp] { dropped.map { UndoOp.insertTask($0) } }

    private func monthSessions(_ t: Tutor) -> [TutorSession] {
        store.tutorSessions.filter { $0.tutorID == t.id && cal.isDate($0.date, equalTo: .now, toGranularity: .month) }
    }

    private func canonicalExercise(_ name: String) -> String {
        let n = Planner.normalize(name)
        return Program.allExerciseNames.first { Planner.normalize($0) == n }
            ?? Program.allExerciseNames.first { Planner.normalize($0).contains(n) || n.contains(Planner.normalize($0)) }
            ?? name
    }

    private func fallbackText(_ items: [JournalItem]) -> String {
        if items.isEmpty { return "👍" }
        return items.map { ($0.status == .applied ? "✅ " : $0.status == .proposed ? "💡 " : "⚠️ ") + $0.summary }.joined(separator: "\n")
    }
}
