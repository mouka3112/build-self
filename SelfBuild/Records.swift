import Foundation

/// Une donnée de l'app, quel que soit son module : sert aux actions génériques
/// `.add`, `.update`, `.delete` du moteur (et à leur annulation exacte).
enum Record: Codable, Hashable {
    case txn(Txn), food(FoodEntry), homework(Homework), exam(ExamItem), reminder(UserReminder), tutor(Tutor)
    case timetable(TimetableEntry), note(NoteItem), health(HealthEntry), lesson(LessonPhoto), runRecord(RunRecord)
    case project(Project), customFood(FoodCard), workoutSet(SetRecord), clothing(ClothingItem), review(SessionReview)
    case challenge(Challenge), capsule(TimeCapsule), dish(DishLog), tutorSession(TutorSession)

    var ref: RecordRef {
        switch self {
        case .txn(let x): return .txn(x.id)
        case .food(let x): return .food(x.id)
        case .homework(let x): return .homework(x.id)
        case .exam(let x): return .exam(x.id)
        case .reminder(let x): return .reminder(x.id)
        case .tutor(let x): return .tutor(x.id)
        case .timetable(let x): return .timetable(x.id)
        case .note(let x): return .note(x.id)
        case .health(let x): return .health(x.id)
        case .lesson(let x): return .lesson(x.id)
        case .runRecord(let x): return .runRecord(x.id)
        case .project(let x): return .project(x.id)
        case .customFood(let x): return .customFood(x.id)
        case .workoutSet(let x): return .workoutSet(x.id)
        case .clothing(let x): return .clothing(x.id)
        case .review(let x): return .review(x.id)
        case .challenge(let x): return .challenge(x.id)
        case .capsule(let x): return .capsule(x.id)
        case .dish(let x): return .dish(x.id)
        case .tutorSession(let x): return .tutorSession(x.id)
        }
    }

    /// Libellé lisible pour le Journal.
    var label: String {
        switch self {
        case .txn(let x): return "\(x.amount < 0 ? "dépense" : "revenu") \(String(format: "%.2f", abs(x.amount))) (\(x.category))"
        case .food(let x): return "\(x.name) \(Int(x.grams)) g"
        case .homework(let x): return "devoir \(x.subject) – \(x.title)"
        case .exam(let x): return "contrôle de \(x.subject) (\(Fmt.dayMonth(x.date)))"
        case .reminder(let x): return "rappel « \(x.title) »"
        case .tutor(let x): return "prof \(x.name) (\(x.subject))"
        case .timetable(let x): return "cours de \(x.subject) \(timeString(x.start))-\(timeString(x.end))"
        case .note(let x): return "note « \(String(x.text.prefix(40))) »"
        case .health(let x): return "\(x.kind) : \(x.text)"
        case .lesson(let x): return "photo de cours (\(x.subject))"
        case .runRecord(let x): return String(format: "course de %.2f km", x.distance / 1000)
        case .project(let x): return "projet « \(x.title) »"
        case .customFood(let x): return "carte \(x.name)"
        case .workoutSet(let x): return "série \(x.exercise) \(fmtKg(x.weight)) kg × \(x.reps)"
        case .clothing(let x): return "\(x.name) (\(x.clean ? "propre" : "sale"))"
        case .review(let x): return "bilan de \(x.kind == "workout" ? "séance" : "session")"
        case .challenge(let x): return "défi « \(x.text) »"
        case .capsule(let x): return "capsule (ouverture le \(Fmt.dayMonth(x.unlock)))"
        case .dish(let x): return "plat \(x.name) \(x.score)/10"
        case .tutorSession(_): return "séance de cours particulier"
        }
    }

    var destination: AppDestination { ref.destination }
}

enum RecordRef: Codable, Hashable {
    case txn(UUID), food(UUID), homework(UUID), exam(UUID), reminder(UUID), tutor(UUID)
    case timetable(UUID), note(UUID), health(UUID), lesson(UUID), runRecord(UUID)
    case project(UUID), customFood(String), workoutSet(UUID), clothing(UUID), review(UUID)
    case challenge(UUID), capsule(UUID), dish(UUID), tutorSession(UUID)

    var destination: AppDestination {
        switch self {
        case .txn: return .finance
        case .food, .customFood: return .nutrition
        case .homework: return .study
        case .exam, .timetable: return .school
        case .reminder: return .reminders
        case .tutor, .tutorSession: return .tutors
        case .note: return .notes
        case .health: return .health
        case .lesson: return .lessons
        case .runRecord: return .running
        case .project: return .projects
        case .workoutSet: return .muscu
        case .clothing: return .wardrobe
        case .review: return .reports
        case .challenge: return .challenges
        case .capsule: return .capsule
        case .dish: return .kitchen
        }
    }
}

private func upsertIn<T: Identifiable>(_ list: inout [T], _ item: T) {
    if let i = list.firstIndex(where: { $0.id == item.id }) { list[i] = item } else { list.append(item) }
}

extension AppStore {
    func record(_ ref: RecordRef) -> Record? {
        switch ref {
        case .txn(let id): return txns.first { $0.id == id }.map(Record.txn)
        case .food(let id): return foods.first { $0.id == id }.map(Record.food)
        case .homework(let id): return homework.first { $0.id == id }.map(Record.homework)
        case .exam(let id): return exams.first { $0.id == id }.map(Record.exam)
        case .reminder(let id): return reminders.first { $0.id == id }.map(Record.reminder)
        case .tutor(let id): return tutors.first { $0.id == id }.map(Record.tutor)
        case .timetable(let id): return timetable.first { $0.id == id }.map(Record.timetable)
        case .note(let id): return notes.first { $0.id == id }.map(Record.note)
        case .health(let id): return healthLog.first { $0.id == id }.map(Record.health)
        case .lesson(let id): return lessons.first { $0.id == id }.map(Record.lesson)
        case .runRecord(let id): return runs.first { $0.id == id }.map(Record.runRecord)
        case .project(let id): return projects.first { $0.id == id }.map(Record.project)
        case .customFood(let id): return customFoods.first { $0.id == id }.map(Record.customFood)
        case .workoutSet(let id): return sets.first { $0.id == id }.map(Record.workoutSet)
        case .clothing(let id): return wardrobe.first { $0.id == id }.map(Record.clothing)
        case .review(let id): return reviews.first { $0.id == id }.map(Record.review)
        case .challenge(let id): return challenges.first { $0.id == id }.map(Record.challenge)
        case .capsule(let id): return capsules.first { $0.id == id }.map(Record.capsule)
        case .dish(let id): return dishes.first { $0.id == id }.map(Record.dish)
        case .tutorSession(let id): return tutorSessions.first { $0.id == id }.map(Record.tutorSession)
        }
    }

    /// Ajoute la donnée, ou la remplace si elle existe déjà (même identifiant).
    func upsert(_ r: Record) {
        switch r {
        case .txn(let x): upsertIn(&txns, x)
        case .food(let x): upsertIn(&foods, x)
        case .homework(let x): upsertIn(&homework, x)
        case .exam(let x): upsertIn(&exams, x)
        case .reminder(let x): upsertIn(&reminders, x)
        case .tutor(let x): upsertIn(&tutors, x)
        case .timetable(let x): upsertIn(&timetable, x)
        case .note(let x): upsertIn(&notes, x)
        case .health(let x): upsertIn(&healthLog, x)
        case .lesson(let x): upsertIn(&lessons, x)
        case .runRecord(let x): upsertIn(&runs, x)
        case .project(let x): upsertIn(&projects, x)
        case .customFood(let x): upsertIn(&customFoods, x)
        case .workoutSet(let x): upsertIn(&sets, x)
        case .clothing(let x): upsertIn(&wardrobe, x)
        case .review(let x): upsertIn(&reviews, x)
        case .challenge(let x): upsertIn(&challenges, x)
        case .capsule(let x): upsertIn(&capsules, x)
        case .dish(let x): upsertIn(&dishes, x)
        case .tutorSession(let x): upsertIn(&tutorSessions, x)
        }
    }

    /// Retire la donnée et la renvoie (pour pouvoir l'annuler).
    @discardableResult
    func removeRecord(_ ref: RecordRef) -> Record? {
        guard let old = record(ref) else { return nil }
        switch ref {
        case .txn(let id): txns.removeAll { $0.id == id }
        case .food(let id): foods.removeAll { $0.id == id }
        case .homework(let id): homework.removeAll { $0.id == id }
        case .exam(let id): exams.removeAll { $0.id == id }
        case .reminder(let id): reminders.removeAll { $0.id == id }
        case .tutor(let id): tutors.removeAll { $0.id == id }
        case .timetable(let id): timetable.removeAll { $0.id == id }
        case .note(let id): notes.removeAll { $0.id == id }
        case .health(let id): healthLog.removeAll { $0.id == id }
        case .lesson(let id): lessons.removeAll { $0.id == id }
        case .runRecord(let id): runs.removeAll { $0.id == id }
        case .project(let id): projects.removeAll { $0.id == id }
        case .customFood(let id): customFoods.removeAll { $0.id == id }
        case .workoutSet(let id): sets.removeAll { $0.id == id }
        case .clothing(let id): wardrobe.removeAll { $0.id == id }
        case .review(let id): reviews.removeAll { $0.id == id }
        case .challenge(let id): challenges.removeAll { $0.id == id }
        case .capsule(let id): capsules.removeAll { $0.id == id }
        case .dish(let id): dishes.removeAll { $0.id == id }
        case .tutorSession(let id): tutorSessions.removeAll { $0.id == id }
        }
        return old
    }
}
