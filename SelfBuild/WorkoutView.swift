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
        if let t = store.tasks.first(where: { $0.kind == .workout && !$0.done }) { store.complete(t) }
        else { store.workoutCursor = (store.workoutCursor + 1) % Program.days.count }
        dayIndex = store.workoutCursor
        LiveActivityManager.shared.end()
        rest.stop()
        Haptic.success()
        router.wrapUp = WrapUpRequest(kind: "workout")
    }
}

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
                    Text("\(fmtKg(s.weight)) kg × \(s.reps)").monospacedDigit()
                }.font(.subheadline)
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
        store.sets.append(SetRecord(date: .now, exercise: ex.name, weight: w, reps: r))
        reps = ""
        rest.start(90)
        Haptic.success()
    }

    private func loadTips() {
        loadingTips = true
        Task {
            do {
                tips = try await gemini.text("""
                Explique l'exercice « \(ex.name) » à un débutant de 15 ans : muscles travaillés, 4 étapes d'exécution, 3 erreurs fréquentes, respiration, et une charge de départ prudente. Maximum 130 mots, listes courtes, français.
                """, store: nil)
            } catch { tips = error.localizedDescription }
            loadingTips = false
        }
    }
}
