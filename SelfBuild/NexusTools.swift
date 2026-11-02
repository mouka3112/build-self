import Foundation

/// Valeur JSON renvoyée par Gemini (arguments d'un appel de fonction).
enum JSONValue: Hashable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    init(_ any: Any?) {
        guard let any else { self = .null; return }
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) } else { self = .number(n.doubleValue) }
        } else if let s = any as? String {
            self = .string(s)
        } else if let a = any as? [Any] {
            self = .array(a.map { JSONValue($0) })
        } else if let o = any as? [String: Any] {
            self = .object(o.mapValues { JSONValue($0) })
        } else {
            self = .null
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let s): return s.trimmingCharacters(in: .whitespacesAndNewlines)
        case .number(let d): return d == d.rounded() && abs(d) < 1e12 ? String(Int(d)) : String(d)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }
    var doubleValue: Double? {
        switch self {
        case .number(let d): return d.isFinite ? d : nil
        case .string(let s):
            let clean = s.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." || $0 == "-" }
            return Double(clean)
        default: return nil
        }
    }
    var intValue: Int? {
        guard let d = doubleValue, abs(d) < 1e9 else { return nil }
        return Int(d.rounded())
    }
    var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .string(let s): return ["true", "oui", "1"].contains(s.lowercased())
        default: return nil
        }
    }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
}

struct ToolCall {
    let name: String
    let args: [String: JSONValue]
}

/// Fonctions déclarées à Gemini (function calling) + validation stricte des arguments côté app.
enum NexusTools {

    // MARK: Déclarations (schéma envoyé à l'API)
    private static func str(_ d: String, _ values: [String]? = nil) -> [String: Any] {
        var s: [String: Any] = ["type": "string", "description": d]
        if let values { s["format"] = "enum"; s["enum"] = values }
        return s
    }
    private static func num(_ d: String) -> [String: Any] { ["type": "number", "description": d] }
    private static func int(_ d: String) -> [String: Any] { ["type": "integer", "description": d] }
    private static func bool(_ d: String) -> [String: Any] { ["type": "boolean", "description": d] }
    private static func arr(_ d: String, _ items: [String: Any]) -> [String: Any] { ["type": "array", "description": d, "items": items] }
    private static func obj(_ props: [String: [String: Any]], _ required: [String]) -> [String: Any] {
        ["type": "object", "properties": props, "required": required] as [String: Any]
    }
    private static func fn(_ name: String, _ desc: String, _ props: [String: [String: Any]] = [:], _ required: [String] = []) -> [String: Any] {
        var f: [String: Any] = ["name": name, "description": desc]
        if !props.isEmpty { f["parameters"] = obj(props, required) }
        return f
    }

    private static let confirmDesc = "true = c'est TA suggestion (non affirmée/demandée par l'utilisateur) : l'app affiche un bouton pour qu'il confirme. Absent/false = il l'a affirmé ou demandé explicitement."
    static let taskKinds = ["study", "workout", "meal", "hygiene", "rest", "other"]
    static let habitValues = HygieneHabit.allCases.map(\.rawValue)
    static let screens = AppDestination.allCases.map(\.rawValue)

    static func declarations() -> [[String: Any]] {
        let confirm = bool(confirmDesc)
        let mealItem = obj(["name": str("Nom de l'aliment"), "grams": num("Quantité en grammes"),
                            "kcal": num("Calories TOTALES de cette quantité"), "protein": num("Protéines TOTALES en g")],
                           ["name", "grams", "kcal", "protein"])
        let slot = obj(["task": str("Identifiant #XXXX ou titre de la tâche existante"),
                        "start": str("Nouvelle heure de début HH:mm"), "duration": int("Durée en minutes (optionnel)")],
                       ["task", "start"])
        return [
            fn("log_expense", "Enregistre une dépense que l'utilisateur affirme avoir faite.",
               ["amount": num("Montant positif"), "category": str("Catégorie", Finance.categoryNames), "note": str("Détail court")],
               ["amount", "category"]),
            fn("log_income", "Enregistre de l'argent reçu.", ["amount": num("Montant positif"), "note": str("Origine")], ["amount"]),
            fn("log_meal", "Enregistre ce que l'utilisateur a mangé (estime grammes, kcal et protéines TOTALES par aliment).",
               ["items": arr("Aliments mangés", mealItem)], ["items"]),
            fn("log_water", "Enregistre de l'eau bue.", ["ml": int("Millilitres")], ["ml"]),
            fn("log_hygiene", "Valide une ou plusieurs habitudes d'hygiène faites (teethAM/teethPM = dents matin/soir, faceAM/facePM = visage, shower = douche, hair = soin cheveux). Choisis matin/soir selon l'heure.",
               ["habits": arr("Habitudes faites", str("Habitude", habitValues))], ["habits"]),
            fn("complete_task", "Marque une tâche du planning du jour comme terminée.", ["task": str("Identifiant #XXXX ou titre")], ["task"]),
            fn("start_task", "L'utilisateur commence une tâche maintenant (la suite du planning se décale).", ["task": str("Identifiant #XXXX ou titre")], ["task"]),
            fn("add_task", "Ajoute une tâche au planning du jour.",
               ["title": str("Titre"), "start": str("Heure HH:mm"), "duration": int("Minutes"), "kind": str("Type", taskKinds), "confirm": confirm],
               ["title", "start", "duration"]),
            fn("remove_task", "Retire une tâche du planning du jour.", ["task": str("Identifiant #XXXX ou titre"), "confirm": confirm], ["task"]),
            fn("replan_day", "Propose une réorganisation du reste de la journée (affichée avec un bouton « Appliquer »). Ne touche jamais aux cours, cours particuliers ni au sommeil. Créneaux à partir de maintenant, sans chevauchement.",
               ["slots": arr("Nouveaux créneaux", slot), "reason": str("Pourquoi, en une phrase")], ["slots"]),
            fn("switch_activity", "L'utilisateur fait autre chose maintenant pendant X minutes : décale toute la suite.",
               ["activity": str("Activité"), "minutes": int("Durée en minutes"), "confirm": confirm], ["activity", "minutes"]),
            fn("log_workout_set", "Enregistre une série de musculation.",
               ["exercise": str("Nom de l'exercice (de préférence celui du programme)"), "weight": num("Charge en kg (0 = poids du corps)"),
                "reps": int("Répétitions"), "effort": int("Effort ressenti : 1 facile, 2 correct, 3 dur")],
               ["exercise", "weight", "reps"]),
            fn("log_health", "Note une info de santé du jour.",
               ["kind": str("Type", ["Sommeil", "Symptôme", "Médicament", "Énergie", "Autre"]), "text": str("Détail")], ["kind", "text"]),
            fn("add_note", "Ajoute une note.", ["text": str("Contenu")], ["text"]),
            fn("create_reminder", "Crée un rappel avec notification. Calcule la PROCHAINE occurrence à partir de maintenant.",
               ["title": str("Titre court"), "datetime": str("Première occurrence yyyy-MM-dd HH:mm"),
                "repeat": str("Répétition", ["none", "daily", "weekly", "monthly"]), "urgent": bool("Notification urgente"), "confirm": confirm],
               ["title", "datetime"]),
            fn("add_exam", "Ajoute un contrôle/examen à venir.",
               ["subject": str("Matière"), "date": str("yyyy-MM-dd"), "topic": str("Chapitres"), "confirm": confirm], ["subject", "date"]),
            fn("add_homework", "Ajoute un devoir.",
               ["subject": str("Matière"), "title": str("Ce qu'il faut faire"), "due": str("Date de rendu yyyy-MM-dd"), "confirm": confirm],
               ["subject", "title", "due"]),
            fn("complete_homework", "Marque un devoir de la liste comme rendu/fait.", ["homework": str("Matière ou intitulé")], ["homework"]),
            fn("log_tutor_session", "Une séance de cours particulier vient d'avoir lieu.", ["tutor": str("Nom du prof ou matière")], ["tutor"]),
            fn("pay_tutor", "L'utilisateur a payé son prof particulier (« khallast ») : crée la dépense Études et marque les séances payées.",
               ["tutor": str("Nom du prof ou matière")], ["tutor"]),
            fn("complete_challenge", "Valide un micro-défi du jour.", ["challenge": str("Texte ou mot-clé du défi")], ["challenge"]),
            fn("undo_last", "Annule la dernière action enregistrée (si l'utilisateur dit s'être trompé)."),
            fn("navigate_to", "Ouvre l'écran le plus utile maintenant.", ["screen": str("Écran", screens)], ["screen"])
        ]
    }

    // MARK: Conversion + validation d'un appel → action typée
    static func plan(_ call: ToolCall, now: Date = .now) -> PlannedAction {
        let a = call.args
        func s(_ k: String) -> String? { a[k]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } }
        let confirm = a["confirm"]?.boolValue ?? false
        func wrap(_ action: AppAction) -> PlannedAction { confirm ? .propose(action) : .run(action) }
        func bad(_ why: String) -> PlannedAction { .invalid(tool: call.name, reason: why) }

        switch call.name {
        case "log_expense":
            guard let amount = a["amount"]?.doubleValue else { return bad("montant manquant") }
            return .run(.expense(amount: amount, category: s("category") ?? "Autre", note: s("note") ?? ""))
        case "log_income":
            guard let amount = a["amount"]?.doubleValue else { return bad("montant manquant") }
            return .run(.income(amount: amount, note: s("note") ?? ""))
        case "log_meal":
            let items: [MealLine] = (a["items"]?.arrayValue ?? []).compactMap { v in
                guard let o = v.objectValue, let name = o["name"]?.stringValue, !name.isEmpty,
                      let g = o["grams"]?.doubleValue, let k = o["kcal"]?.doubleValue, let p = o["protein"]?.doubleValue else { return nil }
                return MealLine(name: name.prefix(1).uppercased() + name.dropFirst(), grams: g, kcal: k, protein: p)
            }
            guard !items.isEmpty else { return bad("aucun aliment lisible") }
            return .run(.meal(items: items))
        case "log_water":
            guard let ml = a["ml"]?.intValue else { return bad("quantité manquante") }
            return .run(.water(ml: ml))
        case "log_hygiene":
            let habits = (a["habits"]?.arrayValue ?? []).compactMap { $0.stringValue.flatMap(HygieneHabit.init(rawValue:)) }
            guard !habits.isEmpty else { return bad("habitude inconnue") }
            return .run(.hygiene(habits: habits))
        case "complete_task":
            guard let t = s("task") else { return bad("tâche manquante") }
            return .run(.completeTask(ref: t))
        case "start_task":
            guard let t = s("task") else { return bad("tâche manquante") }
            return .run(.startTask(ref: t))
        case "add_task":
            guard let title = s("title"), let start = minutes(s("start")) else { return bad("titre ou heure invalide") }
            let kind = TaskKind(rawValue: s("kind") ?? "other") ?? .other
            return wrap(.addTask(title: title, start: start, duration: a["duration"]?.intValue ?? 30, kind: kind))
        case "remove_task":
            guard let t = s("task") else { return bad("tâche manquante") }
            return wrap(.removeTask(ref: t))
        case "replan_day":
            let slots: [PlanSlot] = (a["slots"]?.arrayValue ?? []).compactMap { v in
                guard let o = v.objectValue, let ref = o["task"]?.stringValue, let st = minutes(o["start"]?.stringValue) else { return nil }
                return PlanSlot(ref: ref, start: st, duration: o["duration"]?.intValue)
            }
            guard !slots.isEmpty else { return bad("aucun créneau lisible") }
            return .propose(.replanDay(slots: slots))                 // toujours une proposition
        case "switch_activity":
            guard let title = s("activity"), let m = a["minutes"]?.intValue else { return bad("activité ou durée manquante") }
            return wrap(.switchActivity(title: title, minutes: m))
        case "log_workout_set":
            guard let ex = s("exercise"), let w = a["weight"]?.doubleValue, let r = a["reps"]?.intValue else { return bad("exercice, charge ou reps manquants") }
            return .run(.workoutSet(exercise: ex, weight: w, reps: r, effort: a["effort"]?.intValue))
        case "log_health":
            guard let text = s("text") else { return bad("texte manquant") }
            return .run(.health(kind: s("kind") ?? "Autre", text: text))
        case "add_note":
            guard let text = s("text") else { return bad("texte manquant") }
            return .run(.note(text: text))
        case "create_reminder":
            guard let title = s("title") else { return bad("titre manquant") }
            guard let date = parseDate(s("datetime")) else { return bad("date/heure illisible (attendu yyyy-MM-dd HH:mm)") }
            let rule = s("repeat") ?? "none"
            return wrap(.reminder(title: title, date: date, rule: rule, urgent: a["urgent"]?.boolValue ?? true))
        case "add_exam":
            guard let subject = s("subject"), let date = parseDate(s("date")) else { return bad("matière ou date invalide") }
            return wrap(.exam(subject: subject, date: date, topic: s("topic") ?? ""))
        case "add_homework":
            guard let subject = s("subject"), let title = s("title"), let due = parseDate(s("due")) else { return bad("devoir incomplet") }
            return wrap(.homework(subject: subject, title: title, due: due))
        case "complete_homework":
            guard let h = s("homework") else { return bad("devoir manquant") }
            return .run(.completeHomework(ref: h))
        case "log_tutor_session":
            guard let t = s("tutor") else { return bad("prof manquant") }
            return .run(.tutorSession(ref: t))
        case "pay_tutor":
            guard let t = s("tutor") else { return bad("prof manquant") }
            return .run(.tutorPaid(ref: t))
        case "complete_challenge":
            guard let c = s("challenge") else { return bad("défi manquant") }
            return .run(.completeChallenge(ref: c))
        case "undo_last":
            return .run(.undoLast)
        case "navigate_to":
            guard let d = s("screen").flatMap(AppDestination.init(rawValue:)) else { return bad("écran inconnu") }
            return .run(.navigate(to: d))
        default:
            return bad("fonction inconnue")
        }
    }

    // MARK: Analyse des heures et des dates
    /// "18:30", "18h30", "18h", "18" → minutes depuis minuit.
    static func minutes(_ raw: String?) -> Int? {
        guard var t = raw?.lowercased().trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        t = t.replacingOccurrences(of: "h", with: ":")
        if t.hasSuffix(":") { t += "00" }
        if !t.contains(":") { t += ":00" }
        let p = t.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard p.count >= 2, (0...47).contains(p[0]), (0...59).contains(p[1]) else { return nil }
        return p[0] * 60 + p[1]
    }

    static func parseDate(_ raw: String?) -> Date? {
        guard let s = raw?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for fmt in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
