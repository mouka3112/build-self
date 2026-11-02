import Foundation

/// Contexte compact (< ~2000 tokens) régénéré depuis AppStore à CHAQUE tour :
/// le message suivant voit donc toujours l'état réel, y compris les actions qui viennent d'être exécutées.
/// Volontairement exclus : Safe Space (journal intime) et photos de progression.
@MainActor
enum AIContext {
    private static let maxChars = 6500

    static func build(_ s: AppStore) -> String {
        let cal = Calendar.current
        let now = s.minutesNow
        let df = DateFormatter(); df.locale = Locale(identifier: "fr_FR"); df.dateFormat = "EEE d MMM"
        let iso = DateFormatter(); iso.locale = Locale(identifier: "en_US_POSIX"); iso.dateFormat = "yyyy-MM-dd"
        let dayNames = ["", "dim", "lun", "mar", "mer", "jeu", "ven", "sam"]
        let cur = s.currency
        // (priorité, texte) : on coupe d'abord les sections de faible priorité si le contexte est trop long.
        var sections: [(Int, String)] = []

        // Profil
        let p = s.profileOrDefault
        var prof = "PROFIL : \(s.displayName), \(p.age) ans, \(Int(p.heightCm)) cm, \(fmtKg(p.weightKg)) kg, \(p.cityLabel), monnaie \(cur)."
        if p.isStudent { prof += " Élève" + (p.level.isEmpty ? "" : " en \(p.level)") + (p.school.isEmpty ? "" : " (\(p.school))") + "." }
        if !p.goals.isEmpty { prof += " Objectifs : \(p.goals.joined(separator: ", "))." }
        if !p.goalsNote.isEmpty { prof += " \(p.goalsNote)" }
        prof += " Réveil \(timeString(p.wakeMinute)), coucher \(timeString(p.bedMinute))."
        sections.append((0, prof))

        // Repères de dates (pour calculer les rappels « tous les lundis »…)
        let next = (0..<8).compactMap { off -> String? in
            guard let d = cal.date(byAdding: .day, value: off, to: .now) else { return nil }
            return "\(dayNames[cal.component(.weekday, from: d)]) \(iso.string(from: d))"
        }
        sections.append((0, "CALENDRIER : " + next.joined(separator: ", ")))

        // Planning du jour (statut réel de chaque tâche)
        let active = Planner.active(s.tasks, now: now)
        let current = active.first { $0.start <= now }
        let plan = s.tasks.sorted { $0.start < $1.start }.map { t -> String in
            let status: String
            if t.done { status = "fait" }
            else if Planner.isPastClass(t, now: now) { status = "terminé" }
            else if Planner.isMissed(t, now: now) { status = "manqué" }
            else if t.id == current?.id { status = "EN COURS" }
            else { status = "à venir" }
            return "#\(t.shortID) \(timeString(t.start))-\(timeString(t.end)) \(t.title) [\(status)]"
        }
        var planHead = "PLANNING DU JOUR (Hub, heures actuelles) :"
        if let c = current { planHead += " en cours = #\(c.shortID) \(c.title)." }
        else if let n = active.first { planHead += " prochaine = #\(n.shortID) \(n.title) à \(timeString(n.start))." }
        else { planHead += " tout est terminé." }
        sections.append((0, planHead + "\n" + (plan.isEmpty ? "vide" : plan.joined(separator: "\n"))))

        // École
        if !s.timetable.isEmpty {
            let g = Dictionary(grouping: s.timetable) { $0.weekday }
            let rows = [2, 3, 4, 5, 6, 7, 1].compactMap { wd -> String? in
                guard let list = g[wd] else { return nil }
                return "\(dayNames[wd]) " + list.sorted { $0.start < $1.start }.map { "\(timeString($0.start))-\(timeString($0.end)) \($0.subject)" }.joined(separator: ", ")
            }
            sections.append((2, "EMPLOI DU TEMPS : " + rows.joined(separator: " | ")))
        }
        let ex = s.upcomingExams.prefix(6).map { "\($0.subject) \(df.string(from: $0.date))" + ($0.topic.isEmpty ? "" : " (\($0.topic))") }
        sections.append((1, "CONTRÔLES : " + (ex.isEmpty ? "aucun" : ex.joined(separator: " ; "))))
        let hw = s.pendingHomework.prefix(8).map { "\($0.subject) – \($0.title) (pour \(df.string(from: $0.due)))" }
        sections.append((1, "DEVOIRS À FAIRE : " + (hw.isEmpty ? "aucun" : hw.joined(separator: " ; "))))

        // Cours particuliers
        if !s.tutors.isEmpty {
            let tl = s.tutors.map { t -> String in
                let ms = s.tutorSessions.filter { $0.tutorID == t.id && cal.isDate($0.date, equalTo: .now, toGranularity: .month) }
                let due = Double(ms.filter { !$0.paid }.count) * t.price
                return "\(t.name) (\(t.subject), \(dayNames[t.weekday]) \(timeString(t.hour * 60 + t.minute)), \(Fmt.money(t.price, cur))/séance) : \(ms.count)/\(t.sessionsPerMonth) séances ce mois, \(Fmt.money(due, cur)) dû"
            }
            sections.append((1, "COURS PARTICULIERS : " + tl.joined(separator: " ; ")))
        }

        // Cours photographiés
        let lessons = s.lessons.sorted { $0.date > $1.date }.prefix(6)
        if !lessons.isEmpty {
            let rows = lessons.map { l in "\(l.subject) \(df.string(from: l.date))" + (l.summary.map { " : " + String($0.replacingOccurrences(of: "\n", with: " ").prefix(160)) } ?? "") }
            sections.append((3, "COURS EN PHOTOS (\(s.lessons.count)) : " + rows.joined(separator: " | ")))
        }

        // Muscu
        let day = Program.days[s.workoutCursor % Program.days.count]
        var m = "MUSCU : séance du jour \(day.code) \(day.name) (" + day.exercises.map { "\($0.name) \($0.sets)×\($0.repLabel)" }.joined(separator: ", ") + ")."
        if let w = s.todayWorkout { m += w.done ? " Séance du jour FAITE." : w.kind == .workout ? " Prévue à \(timeString(w.start))." : "" }
        else { m += " Jour de repos." }
        let todaySets = s.sets.filter { cal.isDateInToday($0.date) }
        if !todaySets.isEmpty {
            let byEx = Dictionary(grouping: todaySets) { $0.exercise }
            let rows = byEx.map { (k, v) in "\(k) " + v.map(setLabel).joined(separator: "/") }
            m += " Séries aujourd'hui : " + rows.joined(separator: " ; ") + "."
        }
        let lastDays = Set(s.sets.filter { !cal.isDateInToday($0.date) }.map { cal.startOfDay(for: $0.date) }).sorted(by: >).prefix(3)
        if !lastDays.isEmpty {
            m += " Séances récentes : " + lastDays.map { d in "\(df.string(from: d)) \(s.sets.filter { cal.isDate($0.date, inSameDayAs: d) }.count) séries" }.joined(separator: ", ") + "."
        }
        sections.append((1, m))

        // Nutrition
        let eaten = s.todayFoods.map { "\($0.name) \(Int($0.grams)) g" }
        sections.append((0, "NUTRITION AUJOURD'HUI : \(Int(s.kcalToday))/\(Int(s.calorieGoal)) kcal, \(Int(s.proteinToday))/\(Int(s.proteinGoal)) g protéines. Mangé : "
                         + (eaten.isEmpty ? "rien" : eaten.joined(separator: ", ")) + ". Cartes : " + s.allFoodCards.map(\.name).joined(separator: ", ") + "."))
        sections.append((2, "BILAN 7 JOURS : " + s.stats(days: 7).text.replacingOccurrences(of: "\n", with: " ")))

        // Finances
        let recent = s.txns.sorted { $0.date > $1.date }.prefix(8).map { t in
            "\(df.string(from: t.date)) \(Fmt.signedMoney(t.amount, cur)) \(t.category)" + (t.note.isEmpty ? "" : " (\(t.note))")
        }
        sections.append((0, "FINANCES : solde \(Fmt.money(s.balance, cur)), dépensé ce mois \(Fmt.money(s.monthSpent, cur)). Dernières : " + (recent.isEmpty ? "aucune" : recent.joined(separator: " ; "))))

        // Corps
        let hl = s.healthLog.filter { cal.isDateInToday($0.date) && $0.kind != "Eau" }.map { "\($0.kind) : \($0.text)" }
        sections.append((0, "HYGIÈNE FAITE : \(s.hygieneSummary) (\(s.hygieneDoneCount)/6). SANTÉ : eau \(s.waterToday) ml" + (hl.isEmpty ? "" : ", " + hl.joined(separator: " ; "))))
        let runs = s.runs.sorted { $0.date > $1.date }.prefix(3).map { "\(df.string(from: $0.date)) \(String(format: "%.1f", $0.distance / 1000)) km en \($0.duration / 60) min" }
        if !runs.isEmpty { sections.append((3, "COURSES : " + runs.joined(separator: " ; "))) }

        // Vie quotidienne
        if !s.wardrobe.isEmpty {
            let clean = s.wardrobe.filter { $0.clean }.prefix(15).map(\.name)
            sections.append((3, "GARDE-ROBE PROPRE : " + (clean.isEmpty ? "rien de propre" : clean.joined(separator: ", "))))
        }
        if !s.projects.isEmpty {
            sections.append((3, "PROJETS : " + s.projects.prefix(4).map { "\($0.title) (\($0.steps.filter { $0.done }.count)/\($0.steps.count))" }.joined(separator: " ; ")))
        }
        if !s.challengesToday.isEmpty {
            sections.append((1, "DÉFIS DU JOUR : " + s.challengesToday.map { "\($0.text) [\($0.done ? "fait" : "à faire")]" }.joined(separator: " ; ")))
        }
        if !s.reminders.isEmpty {
            sections.append((2, "RAPPELS : " + s.reminders.sorted { $0.date < $1.date }.prefix(8).map { "\($0.title) – \(Fmt.reminderRule($0.date, $0.repeatRule))" }.joined(separator: " ; ")))
        }
        if !s.notes.isEmpty {
            sections.append((3, "NOTES : " + s.notes.prefix(4).map { String($0.text.prefix(60)).replacingOccurrences(of: "\n", with: " ") }.joined(separator: " | ")))
        }
        if !s.tasteProfile.isEmpty { sections.append((3, "GOÛTS : " + String(s.tasteProfile.prefix(200)))) }

        // Ce qui vient d'être fait (pour ne pas refaire une action)
        let lastActs = s.journal.suffix(6).flatMap { $0.items }.filter { $0.status == .applied }.suffix(5).map(\.summary)
        if !lastActs.isEmpty { sections.append((0, "DERNIÈRES ACTIONS DÉJÀ ENREGISTRÉES : " + lastActs.joined(separator: " | "))) }

        // Budget : on retire les sections les moins prioritaires tant que c'est trop long.
        var kept = sections
        for prio in [3, 2, 1] where kept.map({ $0.1.count }).reduce(0, +) > maxChars {
            kept.removeAll { $0.0 == prio }
        }
        return kept.map { $0.1 }.joined(separator: "\n")
    }

    private static func setLabel(_ r: SetRecord) -> String {
        let faces = ["", "😌", "😅", "🥵"]
        let effort = r.effort.map { faces[min(3, max(0, $0))] } ?? ""
        return "\(fmtKg(r.weight))×\(r.reps)\(effort)"
    }

    static func systemPrompt(_ s: AppStore, tools: Bool) -> String {
        let df = DateFormatter(); df.locale = Locale(identifier: "fr_FR"); df.dateFormat = "EEEE d MMMM yyyy, HH:mm"
        let iso = DateFormatter(); iso.locale = Locale(identifier: "en_US_POSIX"); iso.dateFormat = "yyyy-MM-dd HH:mm"
        let name = s.displayName
        var prompt = """
        Tu es Nexus, le coach de vie intégré à SELF BUILD, l'app de \(name).
        Style : français, tutoiement, direct, chaleureux, concis (≤ 90 mots sauf demande). Conseils adaptés à un adolescent :
        pas de régime extrême, pas de produits dopants, charges prudentes, sommeil 8-9 h, technique avant charges.
        Maintenant : \(df.string(from: .now)) (machine : \(iso.string(from: .now))).

        DONNÉES DE \(name.uppercased()) DANS L'APP (tu y as accès : appuie-toi dessus, ne dis JAMAIS que tu n'y as pas accès) :
        \(build(s))
        (Le Safe Space et les photos de progression ne te sont volontairement jamais transmis.)
        """
        if tools {
            prompt += """


            RÈGLES D'ACTION (fonctions) :
            - Tout ce que \(name) AFFIRME avoir fait ou te DEMANDE explicitement d'enregistrer → appelle la fonction correspondante dans CE tour (plusieurs appels si besoin). Sans appel, rien n'est enregistré.
            - Ce que TU suggères de toi-même → mets confirm=true : l'app affichera un bouton, rien n'est appliqué sans son tap.
            - « réorganise ma journée » → replan_day (toujours affiché comme proposition avec bouton « Appliquer »).
            - Désigne les tâches par leur identifiant #XXXX du planning ci-dessus.
            - « je me suis brossé les dents » → log_hygiene (teethAM avant 14h, teethPM après). « j'ai fini mes devoirs » → complete_task.
            - Repas : estime grammes, kcal et protéines TOTALES par aliment (estimation approximative, dis-le si utile).
            - Rappels : calcule la prochaine occurrence avec le CALENDRIER (ex. « tous les lundis à 18 h » → prochain lundi 18:00, repeat=weekly).
            - Un montant ou une info manque ? Pose la question au lieu d'inventer.
            - Ne refais pas une action listée dans « DERNIÈRES ACTIONS DÉJÀ ENREGISTRÉES ».
            - N'écris JAMAIS de balises ni de JSON dans ton texte. Réponds toujours aussi par une phrase courte qui confirme ou conseille.
            - Si tu sens une détresse sérieuse, encourage avec douceur à parler à un adulte de confiance.
            """
        }
        return prompt
    }
}
