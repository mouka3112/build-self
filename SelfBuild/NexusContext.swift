import Foundation

extension AppStore {
    /// Photo complète de ta vie dans l'app, envoyée à Nexus à chaque message.
    /// Volontairement exclus : Safe Space (journal intime) et photos de progression.
    func nexusContext() -> String {
        let cal = Calendar.current
        let df = DateFormatter(); df.locale = Locale(identifier: "fr_FR"); df.dateFormat = "d MMM"
        let dayNames = ["", "dim", "lun", "mar", "mer", "jeu", "ven", "sam"]
        var L: [String] = []

        // Hub : planning du jour
        let plan = tasks.sorted { $0.start < $1.start }.map { t in
            "\(timeString(t.start))-\(timeString(t.end)) \(t.title) [\(t.done ? "fait" : "à faire")]"
        }
        L.append("PLANNING D'AUJOURD'HUI (Hub) : " + (plan.isEmpty ? "vide" : plan.joined(separator: " ; ")))

        // École
        if !timetable.isEmpty {
            let g = Dictionary(grouping: timetable) { $0.weekday }
            let rows = [2, 3, 4, 5, 6, 7, 1].compactMap { wd -> String? in
                guard let list = g[wd] else { return nil }
                let cours = list.sorted { $0.start < $1.start }.map { "\(timeString($0.start))-\(timeString($0.end)) \($0.subject)" }
                return "\(dayNames[wd]) : " + cours.joined(separator: ", ")
            }
            L.append("EMPLOI DU TEMPS SCOLAIRE : " + rows.joined(separator: " | "))
        } else {
            L.append("EMPLOI DU TEMPS SCOLAIRE : pas encore renseigné (Plus → Emploi du temps).")
        }
        let ex = upcomingExams.prefix(6).map { e in "\(e.subject) le \(df.string(from: e.date))" + (e.topic.isEmpty ? "" : " (\(e.topic))") }
        L.append("CONTRÔLES : " + (ex.isEmpty ? "aucun" : ex.joined(separator: " ; ")))
        let hw = pendingHomework.prefix(8).map { h in "\(h.subject) – \(h.title) (pour le \(df.string(from: h.due)))" }
        L.append("DEVOIRS À FAIRE : " + (hw.isEmpty ? "aucun" : hw.joined(separator: " ; ")))

        // Cours particuliers
        let tl = tutors.map { t -> String in
            let ms = tutorSessions.filter { $0.tutorID == t.id && cal.isDate($0.date, equalTo: .now, toGranularity: .month) }
            let due = Double(ms.filter { !$0.paid }.count) * t.price
            return "\(t.name) (\(t.subject), \(dayNames[t.weekday]) \(String(format: "%02d:%02d", t.hour, t.minute)), \(String(format: "%.0f", t.price)) TND/séance) : \(ms.count)/\(t.sessionsPerMonth) séances ce mois, \(String(format: "%.0f", due)) TND à payer"
        }
        L.append("COURS PARTICULIERS : " + (tl.isEmpty ? "aucun" : tl.joined(separator: " ; ")))

        // Cours photographiés
        let lessonsSorted = lessons.sorted { $0.date > $1.date }
        if !lessonsSorted.isEmpty {
            let rows = lessonsSorted.prefix(10).map { l in "\(l.subject) (\(df.string(from: l.date)))" + (l.summary.map { " : \($0.replacingOccurrences(of: "\n", with: " "))" } ?? "") }
            L.append("COURS EN PHOTOS (\(lessons.count) au total, résumés récents) : " + rows.joined(separator: " | "))
        }

        // Muscu
        let day = Program.days[workoutCursor % Program.days.count]
        var m = "MUSCULATION : prochaine séance \(day.code) \(day.name) (\(day.exercises.map(\.name).joined(separator: ", ")))."
        let todaySets = sets.filter { cal.isDateInToday($0.date) }
        if !todaySets.isEmpty {
            let byEx = Dictionary(grouping: todaySets) { $0.exercise }
            let rows = byEx.map { (k, v) in "\(k) " + v.map { "\(fmtKg($0.weight))×\($0.reps)" }.joined(separator: "/") }
            m += " Séries faites aujourd'hui : " + rows.joined(separator: " ; ") + "."
        }
        let lastDays = Set(sets.map { cal.startOfDay(for: $0.date) }).sorted(by: >).prefix(3)
        if !lastDays.isEmpty {
            m += " Séances récentes : " + lastDays.map { d in "\(df.string(from: d)) (\(sets.filter { cal.isDate($0.date, inSameDayAs: d) }.count) séries)" }.joined(separator: ", ") + "."
        }
        L.append(m)

        // Nutrition
        let foodRows = todayFoods.map { "\($0.name) \(Int($0.grams)) g" }
        L.append("NUTRITION AUJOURD'HUI : \(Int(kcalToday))/\(Int(calorieGoal)) kcal, \(Int(proteinToday))/\(Int(proteinGoal)) g de protéines. Mangé : " + (foodRows.isEmpty ? "rien d'enregistré" : foodRows.joined(separator: ", ")) + ". Cartes d'aliments : " + allFoodCards.map(\.name).joined(separator: ", "))
        L.append("BILAN 7 JOURS : " + stats(days: 7).text.replacingOccurrences(of: "\n", with: " "))

        // Finances
        let recent = txns.sorted { $0.date > $1.date }.prefix(8).map { t in
            "\(df.string(from: t.date)) \(String(format: "%+.2f", t.amount)) \(t.category)" + (t.note.isEmpty ? "" : " (\(t.note))")
        }
        L.append("FINANCES : solde \(String(format: "%.2f", balance)) TND, dépensé ce mois \(String(format: "%.2f", monthSpent)) TND. Dernières opérations : " + (recent.isEmpty ? "aucune" : recent.joined(separator: " ; ")))

        // Corps & santé
        let water = healthLog.filter { $0.kind == "Eau" && cal.isDateInToday($0.date) }.count * 250
        let hl = healthLog.filter { cal.isDateInToday($0.date) && $0.kind != "Eau" }.map { "\($0.kind) : \($0.text)" }
        L.append("HYGIÈNE FAITE AUJOURD'HUI : \(hygieneSummary). SANTÉ AUJOURD'HUI : eau \(water) ml" + (hl.isEmpty ? "" : ", " + hl.joined(separator: " ; ")))

        // Running
        let runsRecent = runs.sorted { $0.date > $1.date }.prefix(3).map { r in "\(df.string(from: r.date)) : \(String(format: "%.1f", r.distance / 1000)) km en \(r.duration / 60) min" }
        if !runsRecent.isEmpty { L.append("COURSES RÉCENTES : " + runsRecent.joined(separator: " ; ")) }

        // Garde-robe, projets, défis, rappels, notes
        let clean = wardrobe.filter { $0.clean }.prefix(20).map(\.name)
        if !wardrobe.isEmpty { L.append("GARDE-ROBE (habits propres) : " + (clean.isEmpty ? "aucun propre" : clean.joined(separator: ", "))) }
        if !projects.isEmpty {
            L.append("PROJETS : " + projects.prefix(5).map { p in "\(p.title) (\(p.steps.filter { $0.done }.count)/\(p.steps.count) étapes)" }.joined(separator: " ; "))
        }
        if !challengesToday.isEmpty {
            L.append("DÉFIS DU JOUR : " + challengesToday.map { "\($0.text) [\($0.done ? "fait" : "à faire")]" }.joined(separator: " ; "))
        }
        if !reminders.isEmpty {
            L.append("RAPPELS ACTIFS : " + reminders.sorted { $0.date < $1.date }.prefix(8).map { r in
                "\(r.title) – \(r.date.formatted(date: .abbreviated, time: .shortened))" + (r.repeatRule == "none" ? "" : " (\(r.repeatRule))")
            }.joined(separator: " ; "))
        }
        if !notes.isEmpty {
            L.append("DERNIÈRES NOTES : " + notes.prefix(5).map { String($0.text.prefix(70)).replacingOccurrences(of: "\n", with: " ") }.joined(separator: " | "))
        }
        L.append("GOÛTS CULINAIRES : " + (tasteProfile.isEmpty ? "inconnus" : tasteProfile))
        return L.joined(separator: "\n")
    }
}
