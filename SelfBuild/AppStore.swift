import Foundation
import Combine
import SwiftUI

private struct Snapshot: Codable {
    var tasks: [TaskItem]; var tasksDate: Date
    var sets: [SetRecord]; var foods: [FoodEntry]
    var homework: [Homework]; var txns: [Txn]; var notes: [NoteItem]
    var workoutCursor: Int; var calorieGoal: Double; var proteinGoal: Double
    var lockdownActive: Bool; var lockdownEnd: Date?
    // v2 : optionnels pour rester compatibles avec les anciennes sauvegardes
    var customFoods: [FoodCard]?; var wardrobe: [ClothingItem]?; var dishes: [DishLog]?
    var tasteProfile: String?; var kitchenStock: String?; var runs: [RunRecord]?
    var projects: [Project]?; var challenges: [Challenge]?; var capsules: [TimeCapsule]?
    var dayLogs: [DayLog]?; var healthLog: [HealthEntry]?; var reviews: [SessionReview]?
    var hygieneLog: [HygieneLog]?
}

@MainActor
final class AppStore: ObservableObject {
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

    private var bag = Set<AnyCancellable>()
    private let key = "selfbuild.snapshot.v1"

    init() {
        load()
        rolloverIfNeeded()
        objectWillChange
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &bag)
    }

    // MARK: Dérivés
    var pending: [TaskItem] { tasks.filter { !$0.done }.sorted { $0.start < $1.start } }
    var pendingHomework: [Homework] { homework.filter { !$0.done }.sorted { $0.due < $1.due } }
    var todayFoods: [FoodEntry] { foods.filter { Calendar.current.isDateInToday($0.date) } }
    var kcalToday: Double { todayFoods.reduce(0) { $0 + $1.kcal } }
    var proteinToday: Double { todayFoods.reduce(0) { $0 + $1.protein } }
    var balance: Double { txns.reduce(0) { $0 + $1.amount } }
    var monthSpent: Double {
        txns.filter { $0.amount < 0 && Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
            .reduce(0) { $0 - $1.amount }
    }
    var minutesNow: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: .now)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
    var allFoodCards: [FoodCard] { FoodCard.all + customFoods }
    var challengesToday: [Challenge] { challenges.filter { Calendar.current.isDateInToday($0.date) } }

    // MARK: Hygiène
    func hygieneDone(_ h: HygieneHabit, on d: Date = .now) -> Bool {
        hygieneLog.contains { $0.habit == h.rawValue && Calendar.current.isDate($0.date, inSameDayAs: d) }
    }
    func setHygiene(_ h: HygieneHabit, _ on: Bool) {
        if on {
            if !hygieneDone(h) { hygieneLog.append(HygieneLog(date: .now, habit: h.rawValue)) }
        } else {
            hygieneLog.removeAll { $0.habit == h.rawValue && Calendar.current.isDateInToday($0.date) }
        }
    }
    var hygieneSummary: String {
        let done = HygieneHabit.allCases.filter { hygieneDone($0) }.map(\.title)
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

    func resetToday() {
        tasks = Self.defaultSchedule(date: .now, workoutIndex: workoutCursor)
        tasksDate = .now
    }

    /// Modifie ici les horaires de ta journée type.
    static func defaultSchedule(date: Date, workoutIndex: Int) -> [TaskItem] {
        let wd = Calendar.current.component(.weekday, from: date)   // 1 = dimanche
        let isSchool = (2...6).contains(wd)
        let trains = ![1, 4].contains(wd)                           // repos : dimanche & mercredi
        let hairDay = [2, 5, 1].contains(wd)                        // lundi, jeudi, dimanche
        let day = Program.days[workoutIndex % Program.days.count]
        let gymStart = isSchool ? 18 * 60 + 30 : 16 * 60
        let gym = trains
            ? TaskItem(title: "Musculation – \(day.code) \(day.name)", icon: "dumbbell.fill", start: gymStart, duration: 75, kind: .workout)
            : TaskItem(title: "Récupération active (marche + étirements)", icon: "figure.walk", start: gymStart, duration: 45, kind: .rest)
        let shower = TaskItem(title: hairDay ? "Douche + shampoing & soin cheveux" : "Douche", icon: "shower.fill",
                              start: gymStart + (trains ? 75 : 45), duration: 15, kind: .hygiene, habit: hairDay ? "shower,hair" : "shower")

        if isSchool {
            return [
                TaskItem(title: "Réveil & petit-déjeuner", icon: "sunrise.fill", start: 7 * 60, duration: 45, kind: .meal),
                TaskItem(title: "Dents + visage (matin)", icon: "sparkles", start: 7 * 60 + 45, duration: 10, kind: .hygiene, habit: "teethAM,faceAM"),
                TaskItem(title: "Cours – Collège pilote", icon: "graduationcap.fill", start: 8 * 60, duration: 480, kind: .school),
                TaskItem(title: "Repas protéiné", icon: "fork.knife", start: 16 * 60 + 15, duration: 30, kind: .meal),
                TaskItem(title: "Devoirs", icon: "book.fill", start: 16 * 60 + 50, duration: 90, kind: .study),
                gym,
                shower,
                TaskItem(title: "Dîner", icon: "fork.knife", start: 20 * 60, duration: 40, kind: .meal),
                TaskItem(title: "Révisions / lecture", icon: "text.book.closed.fill", start: 20 * 60 + 40, duration: 50, kind: .study),
                TaskItem(title: "Dents + visage (soir)", icon: "sparkles", start: 21 * 60 + 30, duration: 15, kind: .hygiene, habit: "teethPM,facePM"),
                TaskItem(title: "Préparer demain + bilan avec Nexus", icon: "checklist", start: 21 * 60 + 45, duration: 15, kind: .other),
                TaskItem(title: "Sommeil (8-9 h)", icon: "moon.zzz.fill", start: 22 * 60, duration: 540, kind: .sleep)
            ]
        } else {
            return [
                TaskItem(title: "Réveil & petit-déjeuner", icon: "sunrise.fill", start: 8 * 60 + 30, duration: 45, kind: .meal),
                TaskItem(title: "Dents + visage (matin)", icon: "sparkles", start: 9 * 60 + 15, duration: 10, kind: .hygiene, habit: "teethAM,faceAM"),
                TaskItem(title: "Révisions longues", icon: "book.fill", start: 9 * 60 + 30, duration: 120, kind: .study),
                TaskItem(title: "Déjeuner", icon: "fork.knife", start: 12 * 60 + 30, duration: 60, kind: .meal),
                TaskItem(title: "Devoirs / avance sur la semaine", icon: "text.book.closed.fill", start: 14 * 60, duration: 90, kind: .study),
                gym,
                shower,
                TaskItem(title: "Dîner", icon: "fork.knife", start: 19 * 60 + 30, duration: 45, kind: .meal),
                TaskItem(title: "Préparer la semaine", icon: "checklist", start: 20 * 60 + 30, duration: 30, kind: .other),
                TaskItem(title: "Dents + visage (soir)", icon: "sparkles", start: 21 * 60 + 30, duration: 15, kind: .hygiene, habit: "teethPM,facePM"),
                TaskItem(title: "Sommeil (8-9 h)", icon: "moon.zzz.fill", start: 22 * 60, duration: 540, kind: .sleep)
            ]
        }
    }

    func complete(_ task: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[i].done = true
        if task.kind == .workout { workoutCursor = (workoutCursor + 1) % Program.days.count }
        if let hs = task.habit {
            for s in hs.split(separator: ",") { if let h = HygieneHabit(rawValue: String(s)) { setHygiene(h, true) } }
        }
    }

    /// « Je fais autre chose » : enregistre l'activité et décale le reste de la journée.
    func switchActivity(title: String, minutes: Int) {
        let now = minutesNow
        tasks.append(TaskItem(title: title, icon: "bolt.fill", start: now, duration: minutes, kind: .other, done: true))
        var cursor = now + minutes
        var rescheduled: [TaskItem] = []
        for var t in pending {
            if t.kind == .sleep { rescheduled.append(t); continue }
            if t.start < cursor { t.start = cursor }
            cursor = t.end
            if t.start >= 23 * 60 + 30 { continue }
            rescheduled.append(t)
        }
        let done = tasks.filter { $0.done }
        tasks = (done + rescheduled).sorted { $0.start < $1.start }
    }

    // MARK: Nutrition
    func addFood(_ card: FoodCard, grams: Double) {
        foods.append(FoodEntry(date: .now, name: card.name, grams: grams,
                               kcal: card.kcal100 * grams / 100, protein: card.protein100 * grams / 100))
    }
    func removeFood(_ f: FoodEntry) { foods.removeAll { $0.id == f.id } }

    /// Crée automatiquement une carte pour chaque nouvel ingrédient.
    func ensureCard(name: String, grams: Double, kcal: Double, protein: Double) {
        let lower = name.lowercased()
        guard grams > 0,
              !FoodCard.all.contains(where: { $0.name.lowercased() == lower }),
              !customFoods.contains(where: { $0.name.lowercased() == lower }) else { return }
        customFoods.append(FoodCard(id: "custom-\(lower)", name: name, emoji: "🍽️",
                                    kcal100: kcal / grams * 100, protein100: protein / grams * 100,
                                    portion: max(10, (grams / 10).rounded() * 10)))
    }
    func addCustomFood(name: String, grams: Double, kcal100: Double, protein100: Double) {
        foods.append(FoodEntry(date: .now, name: name, grams: grams, kcal: kcal100 * grams / 100, protein: protein100 * grams / 100))
        ensureCard(name: name, grams: grams, kcal: kcal100 * grams / 100, protein: protein100 * grams / 100)
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
        if top.reps >= ex.repMax {
            return (top.weight + 2.5, "Dernière : \(fmtKg(top.weight)) kg × \(top.reps) → monte à \(fmtKg(top.weight + 2.5)) kg")
        }
        return (top.weight, "Dernière : \(fmtKg(top.weight)) kg × \(top.reps) → vise \(ex.repMax) reps")
    }

    // MARK: Persistance
    private func save() {
        let s = Snapshot(tasks: tasks, tasksDate: tasksDate, sets: sets, foods: foods, homework: homework, txns: txns,
                         notes: notes, workoutCursor: workoutCursor, calorieGoal: calorieGoal, proteinGoal: proteinGoal,
                         lockdownActive: lockdownActive, lockdownEnd: lockdownEnd,
                         customFoods: customFoods, wardrobe: wardrobe, dishes: dishes, tasteProfile: tasteProfile,
                         kitchenStock: kitchenStock, runs: runs, projects: projects, challenges: challenges,
                         capsules: capsules, dayLogs: dayLogs, healthLog: healthLog, reviews: reviews, hygieneLog: hygieneLog)
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: key) }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        tasks = s.tasks; tasksDate = s.tasksDate; sets = s.sets; foods = s.foods; homework = s.homework
        txns = s.txns; notes = s.notes; workoutCursor = s.workoutCursor; calorieGoal = s.calorieGoal
        proteinGoal = s.proteinGoal; lockdownActive = s.lockdownActive; lockdownEnd = s.lockdownEnd
        customFoods = s.customFoods ?? []; wardrobe = s.wardrobe ?? []; dishes = s.dishes ?? []
        tasteProfile = s.tasteProfile ?? ""; kitchenStock = s.kitchenStock ?? ""; runs = s.runs ?? []
        projects = s.projects ?? []; challenges = s.challenges ?? []; capsules = s.capsules ?? []
        dayLogs = s.dayLogs ?? []; healthLog = s.healthLog ?? []; reviews = s.reviews ?? []; hygieneLog = s.hygieneLog ?? []
    }
}
