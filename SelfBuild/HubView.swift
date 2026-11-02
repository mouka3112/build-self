import SwiftUI

/// Le Hub : l'app ne demande jamais quoi faire, elle le montre. Tout est lu en direct depuis AppStore.
struct HubView: View {
    @EnvironmentObject var store: AppStore
    @State private var showSwitch = false
    @State private var weather: Weather?

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        HubHeader(weather: weather)
                        NexusSaidBanner()
                        TimelineView(.periodic(from: .now, by: 30)) { ctx in
                            HubNowSection(minute: Fmt.minutesOf(ctx.date), showSwitch: $showSwitch)
                        }
                        HubTiles()
                        HubPlanList()
                        JournalPreview()
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .hideKeyboardOnTap()
        .sheet(isPresented: $showSwitch) { SwitchActivitySheet().presentationDetents([.medium, .large]) }
        .task(id: store.profile?.city) {
            let p = store.profileOrDefault
            weather = await WeatherService.fetch(lat: p.latitude, lon: p.longitude)
        }
    }
}

// MARK: - En-tête
private struct HubHeader: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var live = LiveActivityManager.shared
    let weather: Weather?

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(ctx.date, format: .dateTime.hour().minute())
                        .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                }
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    if let w = weather {
                        Label("\(Int(w.temp.rounded()))° \(store.profileOrDefault.city)", systemImage: w.icon)
                    }
                    if live.isActive { Label("Dynamic Island", systemImage: "circle.fill") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            MascotView(thinking: false, size: 56)
        }
    }
}

// MARK: - Carte EN COURS / À VENIR (recalculée toutes les 30 s depuis l'heure réelle)
private struct HubNowSection: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var router: Router
    let minute: Int
    @Binding var showSwitch: Bool

    var body: some View {
        let active = Planner.active(store.tasks, now: minute)
        VStack(spacing: 12) {
            if let current = active.first {
                TaskNowCard(task: current, minute: minute)
                if let next = active.dropFirst().first { NextTaskRow(task: next, minute: minute) }
                HStack(spacing: 10) {
                    Button { showSwitch = true } label: { Label("Je fais autre chose", systemImage: "arrow.triangle.branch") }
                        .buttonStyle(GlassButtonStyle())
                    Button {
                        router.pendingPrompt = "Réorganise le reste de ma journée à partir de maintenant, en tenant compte de ce que j'ai déjà fait."
                    } label: { Label("Réorganiser", systemImage: "sparkles") }
                        .buttonStyle(GlassButtonStyle())
                }
            } else {
                DoneCard()
            }
        }
    }
}

private struct TaskNowCard: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var router: Router
    let task: TaskItem
    let minute: Int

    var body: some View {
        let upcoming = task.start > minute + 1
        VStack(alignment: .leading, spacing: 14) {
            Text(upcoming ? "À VENIR · dans \(Self.delay(task.start - minute))" : "EN COURS · fin à \(timeString(task.end))")
                .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Image(systemName: task.icon).font(.system(size: 34)).frame(width: 44)
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(.system(.title2, design: .rounded).weight(.bold))
                    Text("\(timeString(task.start)) – \(timeString(task.end)) · \(task.duration) min").foregroundStyle(.secondary)
                }
            }
            if upcoming && !task.isFixed {
                HStack(spacing: 10) {
                    Button { store.engine.apply(.startTask(ref: task.id.uuidString)); Haptic.tap() } label: {
                        Label("Commencer maintenant", systemImage: "play.fill")
                    }
                    .buttonStyle(GlassButtonStyle(prominent: true))
                    Button { finish() } label: { Image(systemName: "checkmark") }
                        .buttonStyle(GlassButtonStyle()).frame(width: 70)
                }
            } else if upcoming {
                Text("Horaire fixe. Profite du temps libre ou avance sur autre chose.").font(.footnote).foregroundStyle(.secondary)
            } else if task.kind == .school {
                Text("Cours en cours : le Hub passe à la suite tout seul à \(timeString(task.end)).").font(.footnote).foregroundStyle(.secondary)
            } else if task.kind == .sleep {
                Text("Bonne nuit 🌙 Pose le téléphone.").font(.footnote).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    if [.workout, .study, .other, .rest].contains(task.kind) {
                        Button { start() } label: { Text(task.kind == .study ? "Mode Focus" : "Démarrer") }
                            .buttonStyle(GlassButtonStyle())
                    }
                    Button { finish() } label: { Label("Terminé", systemImage: "checkmark") }
                        .buttonStyle(GlassButtonStyle(prominent: true))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(30)
    }

    private var accent: Color {
        switch task.kind {
        case .workout: return AppDestination.muscu.color
        case .meal: return AppDestination.nutrition.color
        case .study, .school, .tutor: return AppDestination.study.color
        case .hygiene: return AppDestination.hygiene.color
        case .rest: return AppDestination.running.color
        default: return .white
        }
    }

    static func delay(_ m: Int) -> String { m < 60 ? "\(m) min" : "\(m / 60) h \(String(format: "%02d", m % 60))" }

    private func start() {
        Haptic.tap()
        if task.startedAt == nil { store.engine.apply(.startTask(ref: task.id.uuidString)) }
        let fresh = store.tasks.first { $0.id == task.id } ?? task
        let remaining = max(5, fresh.end - store.minutesNow)
        if task.kind == .workout {
            LiveActivityManager.shared.start(mode: "workout", title: task.title, subtitle: "Entraînement en cours", minutes: remaining)
            router.go(.muscu)
        } else {
            LiveActivityManager.shared.start(mode: "focus", title: task.title, subtitle: task.kind == .study ? "Mode Focus" : "En cours", minutes: remaining)
        }
    }

    private func finish() {
        let r = store.engine.apply(.completeTask(ref: task.id.uuidString))
        LiveActivityManager.shared.end()
        guard r.status == .applied else { Haptic.warn(); return }
        Haptic.success()
        if task.kind == .workout { router.wrapUp = WrapUpRequest(kind: "workout") }
        else if task.kind == .study { router.wrapUp = WrapUpRequest(kind: "study") }
    }
}

/// Tâche suivante avec son heure ACTUALISÉE (lue dans l'état réel, jamais l'heure initiale).
private struct NextTaskRow: View {
    let task: TaskItem
    let minute: Int
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.icon).font(.title3).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("ENSUITE").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                Text(task.title).font(.headline).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(timeString(task.start)).monospacedDigit()
                if task.start > minute { Text("dans \(TaskNowCard.delay(task.start - minute))").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .padding(16)
        .glassCard(22)
    }
}

private struct DoneCard: View {
    @EnvironmentObject var router: Router
    var body: some View {
        VStack(spacing: 14) {
            Text("Planning terminé ✅").font(.system(.title2, design: .rounded).weight(.bold))
            Text("Tout est fait pour aujourd'hui.").foregroundStyle(.secondary)
            Button {
                router.pendingPrompt = "Mon planning du jour est terminé. Que me conseilles-tu de faire maintenant ?"
            } label: { Label("Demander à Nexus quoi faire", systemImage: "sparkles") }
                .buttonStyle(GlassButtonStyle(prominent: true))
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassCard(30)
    }
}

// MARK: - Tuiles synchronisées (lecture directe d'AppStore)
private struct HubTiles: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var router: Router

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            tile(.nutrition, "flame.fill", "\(Int(store.kcalToday)) kcal · \(Int(store.proteinToday)) g",
                 "sur \(Int(store.calorieGoal)) kcal · \(Int(store.proteinGoal)) g prot.")
            tile(.finance, "banknote.fill", Fmt.money(store.balance, store.currency), "solde · \(Fmt.money(store.monthSpent, store.currency)) ce mois")
            tile(.study, "book.closed.fill", "\(store.pendingHomework.count) devoir(s)",
                 store.pendingHomework.first.map { "prochain : \($0.subject) \(Fmt.dayMonth($0.due))" } ?? "rien à rendre")
            tile(.hygiene, "shower.fill", "Hygiène \(store.hygieneDoneCount)/6", store.hygieneSummary)
            tile(.muscu, "dumbbell.fill", workoutValue, workoutLabel)
            tile(.school, "calendar", store.nextClass.map { $0.entry.subject } ?? "—",
                 store.nextClass.map { "prochain cours · \(Fmt.dayMonth($0.date)) \(timeString($0.entry.start))" } ?? "emploi du temps vide")
            tile(.school, "list.clipboard.fill", store.upcomingExams.first.map { "Contrôle \($0.subject)" } ?? "Aucun contrôle",
                 store.upcomingExams.first.map { "le \(Fmt.dayMonth($0.date))" } ?? "rien de prévu")
            tile(.tutors, "person.2.fill", store.nextTutor.map { $0.tutor.subject } ?? "—",
                 store.nextTutor.map { "cours particulier · \(Fmt.dayMonth($0.date)) \(timeString(Fmt.minutesOf($0.date)))" } ?? "aucun prof")
        }
    }

    private var workoutValue: String {
        guard let w = store.todayWorkout else { return "Repos" }
        return w.done ? "Séance faite ✓" : Program.days[store.workoutCursor % Program.days.count].code + " " + Program.days[store.workoutCursor % Program.days.count].name
    }
    private var workoutLabel: String {
        guard let w = store.todayWorkout else { return "récupération active" }
        return w.done ? "bravo 💪" : "prévue à \(timeString(w.start))"
    }

    private func tile(_ dest: AppDestination, _ icon: String, _ value: String, _ label: String) -> some View {
        Button { router.go(dest) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: icon).foregroundStyle(dest.color)
                Text(value).font(.system(.headline, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .glassCard(20)
        }
        .buttonStyle(PressStyle())
        .foregroundStyle(.white)
    }
}

// MARK: - Planning vivant (liste complète du jour)
private struct HubPlanList: View {
    @EnvironmentObject var store: AppStore
    @State private var expanded = true

    var body: some View {
        let now = store.minutesNow
        let current = Planner.active(store.tasks, now: now).first { $0.start <= now }
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation { expanded.toggle() } } label: {
                HStack {
                    Text("PLANNING DU JOUR").font(.caption.weight(.semibold)).tracking(2)
                    Text("\(store.tasks.filter { $0.done }.count)/\(store.tasks.count)").font(.caption).monospacedDigit()
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            if expanded {
                VStack(spacing: 0) {
                    ForEach(store.tasks.filter { !Planner.isPastClass($0, now: now) || $0.done }) { t in
                        PlanRow(task: t, isCurrent: t.id == current?.id, missed: Planner.isMissed(t, now: now))
                        if t.id != store.tasks.last?.id { Divider().opacity(0.2) }
                    }
                }
                .padding(.vertical, 4)
                .glassCard(20)
            }
        }
    }
}

private struct PlanRow: View {
    @EnvironmentObject var store: AppStore
    let task: TaskItem
    let isCurrent: Bool
    let missed: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(timeString(task.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
            Image(systemName: task.icon).font(.caption).frame(width: 18)
            Text(task.title)
                .font(.subheadline.weight(isCurrent ? .bold : .regular))
                .strikethrough(task.done)
                .foregroundStyle(task.done ? Color.secondary : Color.primary)
                .lineLimit(1)
            if missed { Text("manquée").font(.caption2.weight(.semibold)).foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.4)) }
            if isCurrent { Text("en cours").font(.caption2.weight(.semibold)).foregroundStyle(AppDestination.nutrition.color) }
            Spacer(minLength: 4)
            if !task.done && task.kind != .sleep && task.kind != .school {
                Button { _ = store.engine.apply(.completeTask(ref: task.id.uuidString)); Haptic.tap() } label: {
                    Image(systemName: "circle").font(.title3).foregroundStyle(.secondary).frame(width: 36, height: 36)
                }
                .buttonStyle(PressStyle())
            } else if task.done {
                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.secondary).frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .contextMenu {
            if !task.done && !task.isFixed {
                Button { _ = store.engine.apply(.startTask(ref: task.id.uuidString)) } label: { Label("Commencer maintenant", systemImage: "play.fill") }
            }
            if !task.done {
                Button { _ = store.engine.apply(.completeTask(ref: task.id.uuidString)) } label: { Label("Terminé", systemImage: "checkmark") }
                Button(role: .destructive) { _ = store.engine.apply(.removeTask(ref: task.id.uuidString)) } label: { Label("Retirer du planning", systemImage: "trash") }
            }
        }
    }
}

// MARK: - « Je fais autre chose » (activité + durée → réorganisation automatique)
struct SwitchActivitySheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var activity = ""
    @State private var minutes = 30

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Qu'est-ce que tu fais là ?").font(.title2.bold())
                    TextField("Ex : famille, sieste, jeux vidéo…", text: $activity)
                        .padding(14).glassCard(18)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(["Famille", "Amis", "Sport libre", "Sieste", "Jeux vidéo", "Courses", "Mosquée"], id: \.self) { s in
                                Button(s) { activity = s }
                                    .buttonStyle(PressStyle())
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .glassCard(18)
                            }
                        }
                    }
                    Picker("Durée", selection: $minutes) {
                        ForEach([15, 30, 45, 60, 90, 120], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button {
                        let r = store.engine.apply(.switchActivity(title: activity.isEmpty ? "Autre activité" : activity, minutes: minutes))
                        if r.status == .applied { Haptic.success() } else { Haptic.warn() }
                        dismiss()
                    } label: { Text("C'est parti – réorganiser ma journée") }
                        .buttonStyle(GlassButtonStyle(prominent: true))
                    Text("Les cours, cours particuliers et le sommeil ne bougent pas. Le reste glisse après ton activité.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()
            }
            .hideKeyboardOnTap()
        }
    }
}
