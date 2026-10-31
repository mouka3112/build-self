import Foundation
import UIKit

enum TaskKind: String, Codable { case school, study, workout, meal, sleep, rest, hygiene, other }

struct TaskItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var icon: String
    var start: Int          // minutes depuis minuit
    var duration: Int
    var kind: TaskKind
    var done = false
    var habit: String? = nil   // ex : "teethAM,faceAM" (habitudes d'hygiène validées avec la tâche)
    var end: Int { start + duration }
}

struct SetRecord: Identifiable, Codable, Hashable {
    var id = UUID(); var date: Date; var exercise: String; var weight: Double; var reps: Int
}
struct FoodEntry: Identifiable, Codable, Hashable {
    var id = UUID(); var date: Date; var name: String; var grams: Double; var kcal: Double; var protein: Double
}
struct Homework: Identifiable, Codable, Hashable {
    var id = UUID(); var subject: String; var title: String; var due: Date; var done = false
}
struct Txn: Identifiable, Codable, Hashable {
    var id = UUID(); var date: Date; var amount: Double; var category: String; var note: String
}
struct NoteItem: Identifiable, Codable, Hashable {
    var id = UUID(); var date: Date; var text: String
}
struct ChatMessage: Identifiable, Hashable {
    let id = UUID()
    let isUser: Bool
    var text: String
    var image: UIImage? = nil
}

// MARK: - Nouveaux modèles
struct ClothingItem: Identifiable, Codable, Hashable {
    var id = UUID(); var name: String; var category: String; var clean = true
}
struct DishLog: Identifiable, Codable, Hashable {
    var id = UUID(); var date: Date; var name: String; var score: Int; var comment: String; var liked: Bool; var photo: String?
}
struct Coord: Codable, Hashable { var lat: Double; var lon: Double }
struct RunRecord: Identifiable, Codable, Hashable {
    var id = UUID(); var date: Date; var distance: Double; var duration: Int; var route: [Coord]
}
struct RoadmapStep: Identifiable, Codable, Hashable {
    var id = UUID(); var title: String; var done = false
}
struct Project: Identifiable, Codable, Hashable {
    var id = UUID(); var title: String; var goal: String; var steps: [RoadmapStep] = []; var created = Date()
}
struct Challenge: Identifiable, Codable, Hashable {
    var id = UUID(); var date: Date; var text: String; var done = false
}
struct TimeCapsule: Identifiable, Codable, Hashable {
    var id = UUID(); var created: Date; var unlock: Date; var text: String; var photo: String?
}
struct DayLog: Identifiable, Codable, Hashable {
    var id = UUID(); var date: Date; var tasksDone: Int; var tasksTotal: Int; var kcal: Double; var protein: Double; var sets: Int
}
struct HealthEntry: Identifiable, Codable, Hashable {
    var id = UUID(); var date: Date; var kind: String; var text: String
}
struct SessionReview: Identifiable, Codable, Hashable {
    var id = UUID(); var date: Date; var kind: String; var improved: [String]; var worsened: [String]; var note: String; var photo: String?
}
struct HygieneLog: Identifiable, Codable, Hashable {
    var id = UUID(); var date: Date; var habit: String
}
struct SafeEntry: Identifiable, Codable, Hashable {
    var id = UUID(); var date: Date; var text: String; var mood: Int?; var moodLabel: String?; var advice: String?
}

enum HygieneHabit: String, CaseIterable, Identifiable {
    case teethAM, faceAM, teethPM, facePM, shower, hair
    var id: String { rawValue }
    var title: String {
        switch self {
        case .teethAM: return "Brossage des dents – matin"
        case .faceAM: return "Nettoyer le visage – matin"
        case .teethPM: return "Brossage des dents – soir"
        case .facePM: return "Soin du visage – soir"
        case .shower: return "Douche"
        case .hair: return "Soin des cheveux"
        }
    }
    var icon: String {
        switch self {
        case .teethAM, .teethPM: return "sparkles"
        case .faceAM, .facePM: return "face.smiling"
        case .shower: return "shower.fill"
        case .hair: return "drop.fill"
        }
    }
    var tip: String {
        switch self {
        case .teethAM, .teethPM: return "2 minutes, toutes les faces + la langue."
        case .faceAM, .facePM: return "Eau tiède, nettoyant doux, puis hydratant."
        case .shower: return "Savon + shampoing, bien rincer."
        case .hair: return "Shampoing doux, masque ou soin 2-3 fois par semaine."
        }
    }
}

// MARK: - Navigation
enum AppDestination: String, Identifiable, CaseIterable {
    case hub, nexus, muscu, nutrition, plus
    case study, finance, notes, hygiene, wardrobe, kitchen, music, running, projects, challenges, capsule, reports, health, safe, settings
    var id: String { rawValue }
    var tabIndex: Int? {
        switch self {
        case .hub: return 0
        case .nexus: return 1
        case .muscu: return 2
        case .nutrition: return 3
        case .plus: return 4
        default: return nil
        }
    }
    var title: String {
        switch self {
        case .hub: return "Hub"
        case .nexus: return "Nexus"
        case .muscu: return "Musculation"
        case .nutrition: return "Nutrition"
        case .plus: return "Plus"
        case .study: return "Études"
        case .finance: return "Finances"
        case .notes: return "Notes"
        case .hygiene: return "Hygiène"
        case .wardrobe: return "Garde-robe"
        case .kitchen: return "Cuisine"
        case .music: return "Musique & focus"
        case .running: return "Running"
        case .projects: return "Projets"
        case .challenges: return "Micro-défis"
        case .capsule: return "Capsule temporelle"
        case .reports: return "Bilans"
        case .health: return "Santé"
        case .safe: return "Safe Space"
        case .settings: return "Réglages"
        }
    }
    var icon: String {
        switch self {
        case .hub: return "scope"
        case .nexus: return "sparkles"
        case .muscu: return "dumbbell.fill"
        case .nutrition: return "fork.knife"
        case .plus: return "square.grid.2x2.fill"
        case .study: return "graduationcap.fill"
        case .finance: return "banknote.fill"
        case .notes: return "note.text"
        case .hygiene: return "shower.fill"
        case .wardrobe: return "tshirt.fill"
        case .kitchen: return "frying.pan.fill"
        case .music: return "headphones"
        case .running: return "figure.run"
        case .projects: return "map.fill"
        case .challenges: return "flame.fill"
        case .capsule: return "hourglass"
        case .reports: return "chart.pie.fill"
        case .health: return "heart.text.square.fill"
        case .safe: return "lock.shield.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct WrapUpRequest: Identifiable { let id = UUID(); let kind: String }   // "workout" | "study"

// MARK: - Programme Split 5 jours
struct Exercise: Hashable {
    let name: String, sets: Int, repMin: Int, repMax: Int
    var repLabel: String { repMin == repMax ? "\(repMin)" : "\(repMin)-\(repMax)" }
}
struct WorkoutDay: Identifiable { let id: Int; let code: String; let name: String; let exercises: [Exercise] }

private func ex(_ n: String, _ s: Int, _ a: Int, _ b: Int) -> Exercise { Exercise(name: n, sets: s, repMin: a, repMax: b) }

enum Program {
    static let days: [WorkoutDay] = [
        WorkoutDay(id: 0, code: "J1", name: "Pecs / Triceps", exercises: [
            ex("Développé couché", 4, 8, 10), ex("Développé incliné haltères", 3, 8, 12), ex("Écartés poulie", 3, 12, 15),
            ex("Dips", 3, 8, 12), ex("Extension triceps poulie", 3, 10, 15), ex("Barre au front", 3, 10, 12)]),
        WorkoutDay(id: 1, code: "J2", name: "Dos / Biceps", exercises: [
            ex("Tractions", 4, 6, 10), ex("Rowing barre", 4, 8, 10), ex("Tirage horizontal", 3, 10, 12),
            ex("Tirage vertical", 3, 10, 12), ex("Curl barre", 3, 8, 12), ex("Curl marteau", 3, 10, 12)]),
        WorkoutDay(id: 2, code: "J3", name: "Jambes", exercises: [
            ex("Squat", 4, 8, 10), ex("Presse à cuisses", 3, 10, 12), ex("Fentes", 3, 10, 12),
            ex("Leg curl", 3, 10, 15), ex("Mollets debout", 4, 12, 20)]),
        WorkoutDay(id: 3, code: "J4", name: "Épaules / Triceps", exercises: [
            ex("Développé militaire", 4, 8, 10), ex("Élévations latérales", 4, 12, 15), ex("Oiseau", 3, 12, 15),
            ex("Shrugs", 3, 10, 15), ex("Extension triceps poulie", 3, 10, 15), ex("Dips banc", 3, 10, 15)]),
        WorkoutDay(id: 4, code: "J5", name: "Full Body", exercises: [
            ex("Squat", 3, 8, 12), ex("Développé couché", 3, 8, 12), ex("Rowing barre", 3, 8, 12),
            ex("Développé militaire", 3, 10, 12), ex("Curl barre", 2, 10, 12), ex("Extension triceps poulie", 2, 10, 15)])
    ]
}

// MARK: - Cartes nutrition (valeurs moyennes pour 100 g d'aliment cuit)
struct FoodCard: Identifiable, Codable {
    let id: String
    let name: String, emoji: String
    let kcal100: Double, protein100: Double, portion: Double

    static let all: [FoodCard] = [
        FoodCard(id: "dinde", name: "Escalope de dinde", emoji: "🦃", kcal100: 135, protein100: 29, portion: 150),
        FoodCard(id: "poulet", name: "Escalope de poulet", emoji: "🍗", kcal100: 165, protein100: 31, portion: 150),
        FoodCard(id: "riz", name: "Riz blanc", emoji: "🍚", kcal100: 130, protein100: 2.7, portion: 200),
        FoodCard(id: "skyr", name: "Skyr", emoji: "🥛", kcal100: 63, protein100: 11, portion: 150),
        FoodCard(id: "pates", name: "Pâtes", emoji: "🍝", kcal100: 158, protein100: 5.8, portion: 200),
        FoodCard(id: "oeufs", name: "Œufs", emoji: "🥚", kcal100: 143, protein100: 12.6, portion: 100)
    ]
}

enum Finance {
    static let categories: [(name: String, icon: String)] = [
        ("Snacks", "takeoutbag.and.cup.and.straw.fill"), ("Nutrition", "fork.knife"), ("Transport", "bus.fill"),
        ("École", "backpack.fill"), ("Sport", "figure.run"), ("Loisirs", "gamecontroller.fill"), ("Autre", "ellipsis.circle.fill")
    ]
    static let amounts: [Double] = [0.5, 1, 2, 5, 10, 20]
}

let schoolSubjects = ["Arabe", "Français", "Anglais", "Maths", "Physique", "SVT", "Histoire", "Géographie", "Éducation civique", "Informatique", "Technologie"]
