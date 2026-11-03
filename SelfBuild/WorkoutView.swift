import SwiftUI

struct WorkoutView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var rest: RestTimer
    @EnvironmentObject var router: Router
    @State private var dayIndex = 0

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack { ForEach(Program.days) { chip($0) } }
                        }
                        ForEach(Program.days[dayIndex].exercises, id: \.self) { ExerciseCard(ex: $0) }
                        Button { finishSession() } label: { Label("Séance terminée", systemImage: "flag.checkered") }
                            .buttonStyle(GlassButtonStyle(prominent: true))
                        Text("Technique propre d'abord : la charge monte quand les reps cibles sont atteintes.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Musculation")
            .safeAreaInset(edge: .bottom) { if rest.remaining > 0 { RestBar() } }
        }
        .hideKeyboardOnTap()
        .onAppear { dayIndex = store.workoutCursor % Program.days.count }
    }

    @ViewBuilder private func chip(_ d: WorkoutDay) -> some View {
        let sel = dayIndex == d.id
        Button { dayIndex = d.id } label: {
            VStack(spacing: 2) { Text(d.code).font(.headline); Text(d.name).font(.caption2) }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .foregroundStyle(sel ? Color.black : Color.white)
                .background { if sel { Capsule().fill(Color.white) } }
                .overlay { if !sel { Capsule().stroke(Color.white.opacity(0.25)) } }
        }.buttonStyle(PressStyle())
    }

    private func finishSession() {
        store.engine.apply(.finishWorkout)          // tâche du Hub cochée + séance suivante, via le moteur
        dayIndex = store.workoutCursor % Program.days.count
        LiveActivityManager.shared.end()
        rest.stop()
        Haptic.success()
        router.wrapUp = WrapUpRequest(kind: "workout")
    }
}

struct AdaptResult: Decodable { let weight: Double; let reps: Int; let why: String }

struct ExerciseCard: View {
    let ex: Exercise
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var rest: RestTimer
    @EnvironmentObject var gemini: GeminiClient
    @State private var weight = ""
    @State private var reps = ""
    @State private var tips = ""
    @State private var loadingTips = false
    @State private var web: WebLink?
    @State private var effort = 2
    @State private var aiNote = ""
    @State private var adapting = false

    var body: some View {
        let sug = store.suggestion(for: ex)
        let today = store.todaySets(ex.name)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ex.name).font(.headline)
                Spacer()
                Text("\(today.count)/\(ex.sets)").font(.headline.monospacedDigit())
                    .foregroundStyle(today.count >= ex.sets ? Color.white : Color.secondary)
            }
            Text("Cible : \(ex.sets) × \(ex.repLabel) · \(sug.note)").font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    if let u = youtubeSearch("\(ex.name) exercice technique débutant musculation") { web = WebLink(url: u) }
                } label: { Label("Vidéo", systemImage: "play.rectangle.fill").font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 7).glassCard(14) }
                    .buttonStyle(PressStyle())
                Button { loadTips() } label: {
                    Label(loadingTips ? "…" : "Conseils IA", systemImage: "lightbulb.fill").font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 7).glassCard(14)
                }.buttonStyle(PressStyle()).disabled(loadingTips)
            }
            if !tips.isEmpty { Text(tips).font(.footnote).padding(10).glassCard(14) }

            ForEach(Array(today.enumerated()), id: \.element.id) { i, s in
                HStack {
                    Text("Série \(i + 1)").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(fmtKg(s.weight)) kg × \(s.reps)" + (s.effort.map { [" ", " 😌", " 😅", " 🥵"][min(3, max(0, $0))] } ?? "")).monospacedDigit()
                }
                .font(.subheadline)
                .contextMenu { Button("Supprimer la série", role: .destructive) { store.engine.apply(.delete(.workoutSet(s.id))) } }
            }
            if !aiNote.isEmpty { Label(aiNote, systemImage: "sparkles").font(.footnote).padding(10).glassCard(14) }
            HStack(spacing: 8) {
                Text("Effort").font(.caption).foregroundStyle(.secondary)
                ForEach([(1, "😌"), (2, "😅"), (3, "🥵")], id: \.0) { e in
                    Button { effort = e.0 } label: {
                        Text(e.1).font(.title3).padding(6)
                            .background { if effort == e.0 { Circle().fill(Color.white.opacity(0.25)) } }
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button { adapt() } label: {
                    Label(adapting ? "…" : "Nexus adapte", systemImage: "wand.and.stars").font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6).glassCard(12)
                }.buttonStyle(PressStyle()).disabled(adapting)
            }
            HStack(spacing: 10) {
                field("kg", $weight, .decimalPad)
                field("reps", $reps, .numberPad)
                Button { validate() } label: {
                    Image(systemName: "checkmark").font(.headline).foregroundStyle(.black)
                        .frame(width: 48, height: 44).background(Capsule().fill(Color.white))
                }.buttonStyle(PressStyle())
            }
        }
        .padding(16).glassCard(24)
        .onAppear { if weight.isEmpty && sug.weight > 0 { weight = fmtKg(sug.weight) } }
        .sheet(item: $web) { SafariView(url: $0.url).ignoresSafeArea() }
    }

    private func field(_ ph: String, _ text: Binding<String>, _ kb: UIKeyboardType) -> some View {
        TextField(ph, text: text).keyboardType(kb).multilineTextAlignment(.center)
            .frame(height: 44).glassCard(14)
    }

    private func validate() {
        guard let w = Double(weight.replacingOccurrences(of: ",", with: ".")), let r = Int(reps), r > 0 else { Haptic.warn(); return }
        let res = store.engine.apply(.workoutSet(exercise: ex.name, weight: w, reps: r, effort: effort))
        guard res.status == .applied else { aiNote = res.summary; Haptic.warn(); return }
        reps = ""
        rest.start(90)
        Haptic.success()
        if !gemini.apiKey.isEmpty { adapt() }          // Nexus prépare la prochaine série pendant le repos
    }

    /// Nexus choisit la charge et les répétitions à partir de ton historique et de ton effort ressenti.
    private func adapt() {
        adapting = true
        let hist = store.sets.filter { $0.exercise == ex.name }.sorted { $0.date > $1.date }.prefix(14).map { s in
            "\(s.date.formatted(date: .abbreviated, time: .omitted)) : \(fmtKg(s.weight)) kg × \(s.reps)" + (s.effort.map { " (effort \($0)/3)" } ?? "")
        }.joined(separator: " ; ")
        let today = store.todaySets(ex.name).count
        Task {
            do {
                let r = try await gemini.json(AdaptResult.self, """
                Exercice : \(ex.name). Objectif : \(ex.sets) séries de \(ex.repLabel) répétitions (hypertrophie), débutant : \(store.aiPersona).
                Séries déjà faites aujourd'hui : \(today). Historique récent : \(hist.isEmpty ? "aucun (première fois)" : hist).
                Effort : 1 = facile, 2 = correct, 3 = très dur. Règles : progression prudente (+2,5 kg max par séance), si l'effort est 3 deux fois de suite ou si les reps tombent sous le bas de la fourchette, garde ou baisse la charge, technique d'abord.
                Propose la charge et les répétitions pour la PROCHAINE série. JSON uniquement : {"weight": kg en nombre, "reps": répétitions visées, "why": "une phrase courte"}
                """, store: store)
                weight = fmtKg(r.weight); reps = String(r.reps)
                aiNote = "Nexus : \(fmtKg(r.weight)) kg × \(r.reps) – \(r.why)"
            } catch { aiNote = error.localizedDescription }
            adapting = false
        }
    }

    private func loadTips() {
        loadingTips = true
        Task {
            do {
                tips = try await gemini.text("""
                Explique l'exercice « \(ex.name) » à un débutant (\(store.aiPersona)) : muscles travaillés, 4 étapes d'exécution, 3 erreurs fréquentes, respiration, et une charge de départ prudente. Maximum 130 mots, listes courtes, français.
                """, store: nil)
            } catch { tips = error.localizedDescription }
            loadingTips = false
        }
    }
}
