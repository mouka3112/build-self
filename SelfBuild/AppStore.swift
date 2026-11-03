import Foundation
import Combine
import SwiftUI

private struct Snapshot: Codable {
    var tasks: [TaskItem]; var tasksDate: Date
    var sets: [SetRecord]; var foods: [FoodEntry]
    var homework: [Homework]; var txns: [Txn]; var notes: [NoteItem]
    var workoutCursor: Int; var calorieGoal: Double; var proteinGoal: Double
    var lockdownActive: Bool; var lockdownEnd: Date?
    // v2+ : optionnels pour rester compatibles avec les anciennes sauvegardes
    var customFoods: [FoodCard]?; var wardrobe: [ClothingItem]?; var dishes: [DishLog]?
    var tasteProfile: String?; var kitchenStock: String?; var runs: [RunRecord]?
    var projects: [Project]?; var challenges: [Challenge]?; var capsules: [TimeCapsule]?
    var dayLogs: [DayLog]?; var healthLog: [HealthEntry]?; var reviews: [SessionReview]?
    var hygieneLog: [HygieneLog]?
    var tutors: [Tutor]?; var tutorSessions: [TutorSession]?; var exams: [ExamItem]?
    var timetable: [TimetableEntry]?; var reminders: [UserReminder]?; var lessons: [LessonPhoto]?
    // v3
    var profile: UserProfile?; var journal: [JournalEntry]?
}

/// UNIQUE source de vérité. Les vues lisent cet état ; toute modification « métier »
/// passe par `engine.apply(_:)` (ActionEngine), qu'elle vienne de l'UI, de Nexus ou d'une notification.
@MainActor
final class AppStore: ObservableObject {
    /// Pour les délégués système (notifications) qui doivent rejoindre le moteur d'actions.
    static weak var current: AppStore?

    @Published var tasks: [TaskItem] = []
    @Published var tasksDate: Date = .distantPast
    @Published var sets: [SetRecord] = []
    @Published var foods: [FoodEntry] = []
    @Published var homework: [Homework] = []
    @Published var txns: [Txn] = []
    @Published var notes: [NoteItem] = []
    @Published var workoutCursor = 0
    @Published var calorieGoal = 2800.0
    @Published var proteinGoal = 130.0
    @Published var lockdownActive = false
    @Published var lockdownEnd: Date?
    @Published var customFoods: [FoodCard] = []
    @Published var wardrobe: [ClothingItem] = []
    @Published var dishes: [DishLog] = []
    @Published var tasteProfile = ""
    @Published var kitchenStock = ""
    @Published var runs: [RunRecord] = []
    @Published var projects: [Project] = []
    @Published var challenges: [Challenge] = []
    @Published var capsules: [TimeCapsule] = []
    @Published var dayLogs: [DayLog] = []
    @Published var healthLog: [HealthEntry] = []
    @Published var reviews: [SessionReview] = []
    @Published var hygieneLog: [HygieneLog] = []
    @Published var tutors: [Tutor] = []
    @Published var tutorSessions: [TutorSession] = []
    @Published var exams: [ExamItem] = []
    @Published var timetable: [TimetableEntry] = []
    @Published var reminders: [UserReminder] = []
    @Published var lessons: [LessonPhoto] = []
    @Published var profile: UserProfile?
    @Published var journal: [JournalEntry] = []

    private(set) lazy var engine = ActionEngine(store: self)

    private var bag = Set<AnyCancellable>()
    private static let legacyKey = "selfbuild.snapshot.v1"

    init() {
        load()
        rolloverIfNeeded()
        objectWillChange
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &bag)
        AppStore.current = self
    }

    // MARK: Profil
    var needsOnboarding: Bool { profile == nil }
    var profileOrDefault: UserProfile { profile ?? UserProfile() }
    var firstName: String { profile?.firstName.trimmingCharacters(in: .whitespaces) ?? "" }
    var displayName: String { firstName.isEmpty ? "toi" : firstName }
    var currency: String { profile?.currency ?? "TND" }
    var planLimit: Int { Planner.limit(bed: profileOrDefault.bedMinute) }
    /// Matières de l'élève (profil), sinon la liste standard.
    var subjectList: [String] {
        let s = profileOrDefault.subjects
        return s.isEmpty ? schoolSubjects : s
    }
    /// Phrase courte décrivant l'utilisateur pour les prompts IA (jamais de données en dur).
    var aiPersona: String {
        let p = profileOrDefault
        return "\(displayName) (\(p.age) ans, \(Int(p.heightCm)) cm, \(fmtKg(p.weightKg)) kg\(p.isStudent ? ", élève" : ""))"
    }

    func completeOnboarding(_ p: UserProfile, kcal: Double, protein: Double) {
        let firstTime = profile == nil
        profile = p
        calorieGoal = kcal
        proteinGoal = protein
        // Premier lancement : planning généré avec le vrai rythme. Modification depuis Réglages :
        // on garde ce qui est déjà coché (bouton « Régénérer le planning » disponible).
        if firstTime { resetToday() }
        save()
    }

    // MARK: Dérivés (lus en direct par le Hub)
    var minutesNow: Int { Fmt.minutesOf(.now) }
    /// Tâches encore à faire (les cours terminés et les tâches manquées sont exclus).
    var pending: [TaskItem] { Planner.active(tasks, now: minutesNow) }
    var missedTasks: [TaskItem] { Planner.missed(tasks, now: minutesNow) }
    var pendingHomework: [Homework] { homework.filter { !$0.done }.sorted { $0.due < $1.due } }
    var todayFoods: [FoodEntry] { foods.filter { Calendar.current.isDateInToday($0.date) } }
    var kcalToday: Double { todayFoods.reduce(0) { $0 + $1.kcal } }
    var proteinToday: Double { todayFoods.reduce(0) { $0 + $1.protein } }
    var balance: Double { txns.reduce(0) { $0 + $1.amount } }
    var monthSpent: Double {
        txns.filter { $0.amount < 0 && Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
            .reduce(0) { $0 - $1.amount }
    }
    var allFoodCards: [FoodCard] { FoodCard.all + customFoods }
    var challengesToday: [Challenge] { challenges.filter { Calendar.current.isDateInToday($0.date) } }
    var upcomingExams: [ExamItem] {
        let today = Calendar.current.startOfDay(for: .now)
        return exams.filter { $0.date >= today }.sorted { $0.date < $1.date }
    }
    var waterToday: Int {
        healthLog.filter { $0.kind == "Eau" && Calendar.current.isDateInToday($0.date) }.count * 250
    }
    var hygieneDoneCount: Int { HygieneHabit.allCases.filter { hygieneDone($0) }.count }
    var todayWorkout: TaskItem? { tasks.first { $0.kind == .workout } }

    /// Prochain cours de l'emploi du temps (aujourd'hui après maintenant, sinon les jours suivants).
    var nextClass: (entry: TimetableEntry, date: Date)? {
        guard !timetable.isEmpty else { return nil }
        let cal = Calendar.current
        for offset in 0..<8 {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: .now)) else { continue }
            let wd = cal.component(.weekday, from: day)
            let list = timetable.filter { $0.weekday == wd && (offset > 0 || $0.start > minutesNow) }.sorted { $0.start < $1.start }
            if let e = list.first { return (e, Fmt.dateAt(minute: e.start, on: day)) }
        }
        return nil
    }
    /// Prochaine séance de cours particulier (tous profs confondus).
    var nextTutor: (tutor: Tutor, date: Date)? {
        let cal = Calendar.current
        var best: (Tutor, Date)?
        for t in tutors {
            var comps = DateComponents(); comps.weekday = t.weekday; comps.hour = t.hour; comps.minute = t.minute
            let ref = Date().addingTimeInterval(-3600)   // une séance en cours compte encore
            guard let d = cal.nextDate(after: ref, matching: comps, matchingPolicy: .nextTime) else { continue }
            if best == nil || d < best!.1 { best = (t, d) }
        }
        return best.map { (tutor: $0.0, date: $0.1) }
    }

    // MARK: Hygiène
    func hygieneDone(_ h: HygieneHabit, on d: Date = .now) -> Bool {
        hygieneLog.contains { $0.habit == h.rawValue && Calendar.current.isDate($0.date, inSameDayAs: d) }
    }
    /// Utilisé par l'écran Hygiène : cocher passe par le moteur (habitude + tâche du Hub), décocher annule les deux.
    func setHygiene(_ h: HygieneHabit, _ on: Bool) {
        if on { engine.apply(.hygiene(habits: [h])) } else { engine.unsetHygiene(h) }
    }
    var hygieneSummary: String {
        let done = HygieneHabit.allCases.filter { hygieneDone($0) }.map(\.shortTitle)
        return done.isEmpty ? "rien de fait" : done.joined(separator: ", ")
    }

    // MARK: Planning
    func rolloverIfNeeded() {
        guard !Calendar.current.isDateInToday(tasksDate) else { return }
        if tasksDate != .distantPast, !tasks.isEmpty { archiveDay(tasksDate) }
        resetToday()
    }

    private func archiveDay(_ d: Date) {
        let cal = Calendar.current
        let f = foods.filter { cal.isDate($0.date, inSameDayAs: d) }
        dayLogs.append(DayLog(date: cal.startOfDay(for: d), tasksDone: tasks.filter { $0.done }.count, tasksTotal: tasks.count,
                              kcal: f.reduce(0) { $0 + $1.kcal }, protein: f.reduce(0) { $0 + $1.protein },
                              sets: sets.filter { cal.isDate($0.date, inSameDayAs: d) }.count))
    }

    /// Régénère la journée type (emploi du temps, contrôles, devoirs, profs, hygiène, muscu, repas).
    func resetToday() {
        tasks = Planner.generate(date: .now, profile: profileOrDefault, workoutIndex: workoutCursor, timetable: timetable,
                                 exams: exams, homework: homework, tutors: tutors)
        tasksDate = .now
        // Habitudes déjà faites aujourd'hui → tâches déjà cochées.
        for i in tasks.indices where tasks[i].kind == .hygiene && !tasks[i].habits.isEmpty
            && tasks[i].habits.allSatisfy({ hygieneDone($0) }) {
            tasks[i].done = true
        }
    }

    // Raccourcis conservés pour les écrans existants : ils passent tous par le moteur d'actions.
    func complete(_ task: TaskItem) { engine.apply(.completeTask(ref: task.id.uuidString)) }
    func startNow(_ task: TaskItem) { engine.apply(.startTask(ref: task.id.uuidString)) }
    func switchActivity(title: String, minutes: Int) { engine.apply(.switchActivity(title: title, minutes: minutes)) }

    func findPending(_ query: String) -> TaskItem? {
        Planner.match(query, in: pending, now: minutesNow, includeDone: false).map { pending[$0] }
    }

    // MARK: Nutrition
    func addFood(_ card: FoodCard, grams: Double) {
        engine.apply(.meal(items: [MealLine(name: card.name, grams: grams,
                                            kcal: card.kcal100 * grams / 100, protein: card.protein100 * grams / 100)]))
    }
    func removeFood(_ f: FoodEntry) { foods.removeAll { $0.id == f.id } }

    /// Crée automatiquement une carte pour chaque nouvel ingrédient. Renvoie l'id de la carte créée.
    @discardableResult
    func ensureCard(name: String, grams: Double, kcal: Double, protein: Double) -> String? {
        let lower = name.lowercased()
        guard grams > 0,
              !FoodCard.all.contains(where: { $0.name.lowercased() == lower }),
              !customFoods.contains(where: { $0.name.lowercased() == lower }) else { return nil }
        let card = FoodCard(id: "custom-\(lower)", name: name, emoji: "🍽️",
                            kcal100: kcal / grams * 100, protein100: protein / grams * 100,
                            portion: max(10, (grams / 10).rounded() * 10))
        customFoods.append(card)
        return card.id
    }
    func addCustomFood(name: String, grams: Double, kcal100: Double, protein100: Double) {
        engine.apply(.meal(items: [MealLine(name: name, grams: grams, kcal: kcal100 * grams / 100, protein: protein100 * grams / 100)]))
    }

    // MARK: Musculation
    func todaySets(_ exercise: String) -> [SetRecord] {
        sets.filter { $0.exercise == exercise && Calendar.current.isDateInToday($0.date) }
    }

    func suggestion(for ex: Exercise) -> (weight: Double, note: String) {
        let cal = Calendar.current
        let past = sets.filter { $0.exercise == ex.name && !cal.isDateInToday($0.date) }
        guard let lastDay = past.map({ cal.startOfDay(for: $0.date) }).max() else {
            return (0, "Première fois : charge légère, technique parfaite.")
        }
        let day = past.filter { cal.startOfDay(for: $0.date) == lastDay }
        guard let top = day.max(by: { ($0.weight, $0.reps) < ($1.weight, $1.reps) }) else { return (0, "") }
        if top.reps >= ex.repMax && (top.effort ?? 2) < 3 {
            return (top.weight + 2.5, "Dernière : \(fmtKg(top.weight)) kg × \(top.reps) → monte à \(fmtKg(top.weight + 2.5)) kg")
        }
        return (top.weight, "Dernière : \(fmtKg(top.weight)) kg × \(top.reps) → vise \(ex.repMax) reps")
    }

    // MARK: Journal Nexus
    var lastNexusEntry: JournalEntry? { journal.last { $0.source == .nexus } }

    func recordNexusError(userText: String, message: String) {
        journal.append(JournalEntry(source: .nexus, userText: String(userText.prefix(160)), aiText: "⚠️ \(message)", items: []))
        trimJournal()
    }
    func trimJournal() {
        if journal.count > 300 { journal.removeFirst(journal.count - 300) }
    }

    // MARK: Persistance (fichier protégé, migration automatique depuis la v2)
    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("selfbuild-store.json")
    }

    func saveNow() { save() }

    private func save() {
        let s = Snapshot(tasks: tasks, tasksDate: tasksDate, sets: sets, foods: foods, homework: homework, txns: txns,
                         notes: notes, workoutCursor: workoutCursor, calorieGoal: calorieGoal, proteinGoal: proteinGoal,
                         lockdownActive: lockdownActive, lockdownEnd: lockdownEnd,
                         customFoods: customFoods, wardrobe: wardrobe, dishes: dishes, tasteProfile: tasteProfile,
                         kitchenStock: kitchenStock, runs: runs, projects: projects, challenges: challenges,
                         capsules: capsules, dayLogs: dayLogs, healthLog: healthLog, reviews: reviews, hygieneLog: hygieneLog,
                         tutors: tutors, tutorSessions: tutorSessions, exams: exams, timetable: timetable,
                         reminders: reminders, lessons: lessons, profile: profile, journal: journal)
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: Self.fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func load() {
        let decoder = JSONDecoder()
        var snapshot: Snapshot?
        if let data = try? Data(contentsOf: Self.fileURL) { snapshot = try? decoder.decode(Snapshot.self, from: data) }
        if snapshot == nil, let legacy = UserDefaults.standard.data(forKey: Self.legacyKey) {
            snapshot = try? decoder.decode(Snapshot.self, from: legacy)    // données v2 conservées telles quelles
        }
        guard let s = snapshot else { return }
        tasks = s.tasks; tasksDate = s.tasksDate; sets = s.sets; foods = s.foods; homework = s.homework
        txns = s.txns; notes = s.notes; workoutCursor = s.workoutCursor; calorieGoal = s.calorieGoal
        proteinGoal = s.proteinGoal; lockdownActive = s.lockdownActive; lockdownEnd = s.lockdownEnd
        customFoods = s.customFoods ?? []; wardrobe = s.wardrobe ?? []; dishes = s.dishes ?? []
        tasteProfile = s.tasteProfile ?? ""; kitchenStock = s.kitchenStock ?? ""; runs = s.runs ?? []
        projects = s.projects ?? []; challenges = s.challenges ?? []; capsules = s.capsules ?? []
        dayLogs = s.dayLogs ?? []; healthLog = s.healthLog ?? []; reviews = s.reviews ?? []; hygieneLog = s.hygieneLog ?? []
        tutors = s.tutors ?? []; tutorSessions = s.tutorSessions ?? []; exams = s.exams ?? []
        timetable = s.timetable ?? []; reminders = s.reminders ?? []; lessons = s.lessons ?? []
        profile = s.profile; journal = s.journal ?? []
    }
}
