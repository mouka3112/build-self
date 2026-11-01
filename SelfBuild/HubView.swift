import SwiftUI

struct HubView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var router: Router
    @ObservedObject private var live = LiveActivityManager.shared
    @State private var showSwitch = false
    @State private var activity = ""
    @State private var minutes = 30

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        if let current = store.pending.first {
                            currentCard(current)
                            if let next = store.pending.dropFirst().first { nextCard(next) }
                        } else {
                            doneCard
                        }
                        stats
                        Button { showSwitch = true } label: { Label("Je fais autre chose", systemImage: "arrow.triangle.branch") }
                            .buttonStyle(GlassButtonStyle())
                        if !store.pending.isEmpty {
                            Button {
                                router.pendingPrompt = "Réorganise le reste de ma journée en fonction de l'heure actuelle et de ce que j'ai déjà fait."
                                router.selectedTab = 1
                            } label: { Label("Réorganiser avec Nexus", systemImage: "sparkles") }
                                .buttonStyle(GlassButtonStyle())
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .hideKeyboardOnTap()
        .sheet(isPresented: $showSwitch) { switchSheet.presentationDetents([.medium, .large]) }
    }

    // MARK: Sections
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(ctx.date, format: .dateTime.hour().minute())
                        .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                }
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .foregroundStyle(.secondary)
                if live.isActive { Label("Dynamic Island active", systemImage: "circle.fill").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            MascotView(thinking: false, size: 56)
        }
    }

    private func currentCard(_ t: TaskItem) -> some View {
        TimelineView(.periodic(from: .now, by: 20)) { _ in
            let now = store.minutesNow
            let upcoming = t.start > now + 2
            let flexible = t.kind != .school && t.kind != .sleep
            VStack(alignment: .leading, spacing: 14) {
                Text(upcoming ? "À VENIR · dans \(t.start - now) min" : "EN COURS")
                    .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Image(systemName: t.icon).font(.system(size: 34)).frame(width: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.title).font(.system(.title2, design: .rounded).weight(.bold))
                        Text("\(timeString(t.start)) – \(timeString(t.end))").foregroundStyle(.secondary)
                    }
                }
                if upcoming && flexible {
                    HStack(spacing: 10) {
                        Button { store.startNow(t); Haptic.tap() } label: { Label("Commencer maintenant", systemImage: "play.fill") }
                            .buttonStyle(GlassButtonStyle(prominent: true))
                        Button { finish(t) } label: { Image(systemName: "checkmark") }
                            .buttonStyle(GlassButtonStyle()).frame(width: 70)
                    }
                } else if upcoming {
                    Text("Rien à faire pour l'instant, profite !").font(.footnote).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        if t.kind != .sleep && t.kind != .school && t.kind != .hygiene {
                            Button { start(t) } label: { Text(startLabel(t)) }.buttonStyle(GlassButtonStyle())
                        }
                        Button { finish(t) } label: { Label("Terminé", systemImage: "checkmark") }
                            .buttonStyle(GlassButtonStyle(prominent: true))
                    }
                }
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading).glassCard(30)
        }
    }

    private func nextCard(_ t: TaskItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: t.icon).font(.title3).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("ENSUITE").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                Text(t.title).font(.headline)
            }
            Spacer()
            Text(timeString(t.start)).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(16).glassCard(22)
    }

    private var doneCard: some View {
        VStack(spacing: 14) {
            Text("Planning terminé ✅").font(.system(.title2, design: .rounded).weight(.bold))
            Text("Tout est fait pour aujourd'hui. Demande à Nexus quoi faire de ton temps.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button {
                router.pendingPrompt = "Mon planning du jour est terminé. Que me conseilles-tu de faire maintenant ?"
                router.selectedTab = 1
            } label: { Label("Demander à Nexus", systemImage: "sparkles") }
                .buttonStyle(GlassButtonStyle(prominent: true))
        }
        .padding(20).frame(maxWidth: .infinity).glassCard(30)
    }

    private var stats: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            tile("flame.fill", "\(Int(store.kcalToday)) kcal", "sur \(Int(store.calorieGoal))")
            tile("bolt.heart.fill", "\(Int(store.proteinToday)) g", "protéines / \(Int(store.proteinGoal))")
            tile("banknote.fill", String(format: "%.2f TND", store.balance), "solde")
            tile("book.closed.fill", "\(store.pendingHomework.count)", "devoir(s) à rendre")
        }
    }

    private func tile(_ icon: String, _ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).foregroundStyle(.secondary)
            Text(value).font(.system(.headline, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).glassCard(20)
    }

    private var switchSheet: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Qu'est-ce que tu fais là ?").font(.title2.bold())
                    TextField("Ex : jeux vidéo, famille, sieste…", text: $activity)
                        .padding(14).glassCard(18)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(["Famille", "Amis", "Sport libre", "Sieste", "Jeux vidéo", "Courses"], id: \.self) { s in
                                Button(s) { activity = s }.buttonStyle(PressStyle())
                                    .padding(.horizontal, 14).padding(.vertical, 8).glassCard(18)
                            }
                        }
                    }
                    Picker("Durée", selection: $minutes) {
                        ForEach([15, 30, 60, 90], id: \.self) { Text("\($0) min").tag($0) }
                    }.pickerStyle(.segmented)
                    Button {
                        store.switchActivity(title: activity.isEmpty ? "Autre activité" : activity, minutes: minutes)
                        activity = ""; showSwitch = false
                    } label: { Text("C'est parti – réorganiser ma journée") }
                        .buttonStyle(GlassButtonStyle(prominent: true))
                    Spacer()
                }
                .padding()
            }
            .hideKeyboardOnTap()
        }
    }

    // MARK: Actions
    private func startLabel(_ t: TaskItem) -> String {
        switch t.kind {
        case .workout: return "Démarrer"
        case .study: return "Mode Focus"
        default: return "Démarrer"
        }
    }

    private func start(_ t: TaskItem) {
        Haptic.tap()
        let remaining = max(5, t.end - store.minutesNow)
        if t.kind == .workout {
            LiveActivityManager.shared.start(mode: "workout", title: t.title, subtitle: "Entraînement en cours", minutes: remaining)
            router.selectedTab = 2
        } else {
            LiveActivityManager.shared.start(mode: "focus", title: t.title, subtitle: "Mode Focus", minutes: remaining)
        }
    }

    private func finish(_ t: TaskItem) {
        store.complete(t)
        LiveActivityManager.shared.end()
        Haptic.success()
        if t.kind == .workout { router.wrapUp = WrapUpRequest(kind: "workout") }
        else if t.kind == .study { router.wrapUp = WrapUpRequest(kind: "study") }
    }
}
