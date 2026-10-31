import SwiftUI

struct PeriodStats {
    var days = 7
    var sessions = 0, sessionsGoal = 5
    var avgKcal = 0.0, avgProtein = 0.0, proteinDays = 0, foodDays = 0
    var homeworkDone = 0, homeworkTotal = 0
    var hygienePct = 0.0
    var challengesDone = 0, challengesTotal = 0
    var runKm = 0.0
    var spent = 0.0
    var improved: [String: Int] = [:], worsened: [String: Int] = [:]

    var text: String {
        """
        Période : \(days) jours. Séances muscu : \(sessions)/\(sessionsGoal). Calories moy. : \(Int(avgKcal)) kcal/j, protéines moy. : \(Int(avgProtein)) g/j (objectif protéines atteint \(proteinDays)/\(max(foodDays,1)) jours).
        Devoirs rendus : \(homeworkDone)/\(homeworkTotal). Hygiène : \(Int(hygienePct * 100))%. Défis : \(challengesDone)/\(challengesTotal). Course : \(String(format: "%.1f", runKm)) km. Dépenses : \(String(format: "%.2f", spent)) TND.
        Points améliorés : \(improved.map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")). Points en baisse : \(worsened.map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")).
        """
    }
}

extension AppStore {
    func stats(days: Int) -> PeriodStats {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: .now)) ?? .now
        var s = PeriodStats(days: days)
        s.sessions = Set(sets.filter { $0.date >= start }.map { cal.startOfDay(for: $0.date) }).count
        s.sessionsGoal = max(1, Int((Double(days) / 7 * 5).rounded()))
        let byDay = Dictionary(grouping: foods.filter { $0.date >= start }) { cal.startOfDay(for: $0.date) }
        s.foodDays = byDay.count
        if !byDay.isEmpty {
            let kc = byDay.values.map { $0.reduce(0) { $0 + $1.kcal } }, pr = byDay.values.map { $0.reduce(0) { $0 + $1.protein } }
            s.avgKcal = kc.reduce(0, +) / Double(byDay.count); s.avgProtein = pr.reduce(0, +) / Double(byDay.count)
            s.proteinDays = pr.filter { $0 >= proteinGoal * 0.9 }.count
        }
        let hw = homework.filter { $0.due >= start && $0.due <= Date().addingTimeInterval(86400) }
        s.homeworkTotal = hw.count; s.homeworkDone = hw.filter { $0.done }.count
        let hy = hygieneLog.filter { $0.date >= start }.count
        s.hygienePct = min(1, Double(hy) / Double(days * 5))
        let ch = challenges.filter { $0.date >= start }
        s.challengesTotal = ch.count; s.challengesDone = ch.filter { $0.done }.count
        s.runKm = runs.filter { $0.date >= start }.reduce(0) { $0 + $1.distance } / 1000
        s.spent = txns.filter { $0.date >= start && $0.amount < 0 }.reduce(0) { $0 - $1.amount }
        for r in reviews where r.date >= start {
            r.improved.forEach { s.improved[$0, default: 0] += 1 }
            r.worsened.forEach { s.worsened[$0, default: 0] += 1 }
        }
        return s
    }
}

struct RingView: View {
    let value: Double, title: String, detail: String
    var size: CGFloat = 86
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 9)
                Circle().trim(from: 0, to: min(1, max(0.001, value))).stroke(Color.white, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                Text("\(Int(min(1, value) * 100))%").font(.system(size: size * 0.22, weight: .bold, design: .rounded))
            }.frame(width: size, height: size)
            Text(title).font(.caption.weight(.semibold))
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct StoryCard: View {
    let period: String
    let stats: PeriodStats
    let proteinGoal: Double
    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 26) {
                Text("SELF BUILD").font(.system(size: 14, weight: .bold)).tracking(6).foregroundStyle(.white.opacity(0.6))
                Text(period).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
                VStack(spacing: 22) {
                    HStack(spacing: 22) {
                        RingView(value: Double(stats.sessions) / Double(stats.sessionsGoal), title: "Muscu", detail: "\(stats.sessions)/\(stats.sessionsGoal)", size: 100)
                        RingView(value: Double(stats.proteinDays) / Double(max(stats.foodDays, 1)), title: "Nutrition", detail: "\(Int(stats.avgProtein)) g prot/j", size: 100)
                    }
                    HStack(spacing: 22) {
                        RingView(value: stats.homeworkTotal == 0 ? 0 : Double(stats.homeworkDone) / Double(stats.homeworkTotal), title: "Études", detail: "\(stats.homeworkDone)/\(stats.homeworkTotal)", size: 100)
                        RingView(value: stats.hygienePct, title: "Hygiène", detail: "\(Int(stats.hygienePct * 100))%", size: 100)
                    }
                }
                if stats.runKm > 0 { Text(String(format: "%.1f km courus", stats.runKm)).font(.title3.weight(.semibold)).foregroundStyle(.white) }
                Spacer()
                Text("Discipline > motivation.").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
            .padding(32)
        }
        .frame(width: 360, height: 640)
        .environment(\.colorScheme, .dark)
    }
}

struct ReportsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var gemini: GeminiClient
    @State private var days = 7
    @State private var analysis = ""
    @State private var busy = false
    @State private var story: UIImage?
    @State private var showGallery = false

    var body: some View {
        let s = store.stats(days: days)
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Période", selection: $days) { Text("Semaine").tag(7); Text("Mois").tag(30) }.pickerStyle(.segmented)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                        RingView(value: Double(s.sessions) / Double(s.sessionsGoal), title: "Muscu", detail: "\(s.sessions)/\(s.sessionsGoal) séances")
                        RingView(value: Double(s.proteinDays) / Double(max(s.foodDays, 1)), title: "Protéines", detail: "\(s.proteinDays)/\(max(s.foodDays, 1)) jours")
                        RingView(value: s.homeworkTotal == 0 ? 0 : Double(s.homeworkDone) / Double(s.homeworkTotal), title: "Études", detail: "\(s.homeworkDone)/\(s.homeworkTotal) devoirs")
                        RingView(value: s.hygienePct, title: "Hygiène", detail: "\(Int(s.hygienePct * 100))%")
                        RingView(value: s.challengesTotal == 0 ? 0 : Double(s.challengesDone) / Double(s.challengesTotal), title: "Défis", detail: "\(s.challengesDone)/\(s.challengesTotal)")
                        RingView(value: s.runKm / (days == 7 ? 10 : 40), title: "Course", detail: String(format: "%.1f km", s.runKm))
                    }
                    .padding(16).frame(maxWidth: .infinity).glassCard(24)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Détails").font(.headline)
                        Text("Calories moyennes : \(Int(s.avgKcal)) kcal/jour")
                        Text(String(format: "Dépenses : %.2f TND", s.spent))
                        if !s.improved.isEmpty { Text("↑ " + s.improved.sorted { $0.value > $1.value }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")) }
                        if !s.worsened.isEmpty { Text("↓ " + s.worsened.sorted { $0.value > $1.value }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")) }
                    }
                    .font(.footnote).frame(maxWidth: .infinity, alignment: .leading).padding(16).glassCard(24)

                    Button { analyze(s) } label: { Label(busy ? "Nexus analyse…" : "Analyse de Nexus", systemImage: "sparkles") }
                        .buttonStyle(GlassButtonStyle(prominent: true)).disabled(busy)
                    if !analysis.isEmpty { Text(analysis).font(.callout).padding(16).glassCard(22) }

                    Button { makeStory(s) } label: { Label("Créer ma Story", systemImage: "photo.on.rectangle.angled") }.buttonStyle(GlassButtonStyle())
                    if let img = story {
                        Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 360).clipShape(RoundedRectangle(cornerRadius: 18))
                        ShareLink(item: Image(uiImage: img), preview: SharePreview("Mon bilan SELF BUILD", image: Image(uiImage: img))) {
                            Label("Partager (Instagram, Facebook…)", systemImage: "square.and.arrow.up")
                        }.buttonStyle(GlassButtonStyle(prominent: true))
                    }

                    Button { showGallery = true } label: { Label("Photos de progression 🔒", systemImage: "photo.stack") }.buttonStyle(GlassButtonStyle())
                }
                .padding()
            }
        }
        .navigationTitle("Bilans")
        .sheet(isPresented: $showGallery) { ProgressPhotosView() }
    }

    private func analyze(_ s: PeriodStats) {
        busy = true
        Task {
            do {
                analysis = try await gemini.text("""
                Voici mes statistiques : \(s.text)
                Analyse en français (max 150 mots) : 1) 2 bonnes habitudes, 2) 2 mauvaises habitudes ou points faibles, 3) 3 conseils concrets pour la prochaine période. Croise les données (ex : sommeil/hygiène/nutrition/études). Ton direct et motivant.
                """, store: store)
            } catch { analysis = error.localizedDescription }
            busy = false
        }
    }

    @MainActor private func makeStory(_ s: PeriodStats) {
        let r = ImageRenderer(content: StoryCard(period: days == 7 ? "Ma semaine" : "Mon mois", stats: s, proteinGoal: store.proteinGoal))
        r.scale = 3
        story = r.uiImage
    }
}

struct ProgressPhotosView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var unlocked = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                if unlocked {
                    let items = store.reviews.filter { $0.photo != nil }.sorted { $0.date > $1.date }
                    ScrollView {
                        if items.isEmpty { Text("Aucune photo pour l'instant. Tu peux en ajouter à la fin d'une séance.").foregroundStyle(.secondary).padding() }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(items) { r in
                                VStack(spacing: 4) {
                                    if let f = r.photo, let img = PhotoStore.load(f) {
                                        Image(uiImage: img).resizable().scaledToFill().frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 16))
                                    }
                                    Text(r.date, format: .dateTime.day().month(.abbreviated).year()).font(.caption).foregroundStyle(.secondary)
                                }
                                .contextMenu {
                                    Button("Supprimer", role: .destructive) { store.reviews.removeAll { $0.id == r.id } }
                                }
                            }
                        }.padding()
                    }
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "lock.fill").font(.system(size: 44))
                        Button("Déverrouiller") { Task { unlocked = await Biometrics.authenticate(reason: "Voir tes photos de progression") } }
                            .buttonStyle(GlassButtonStyle(prominent: true)).padding(.horizontal, 60)
                    }
                }
            }
            .navigationTitle("Progression")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .task { unlocked = await Biometrics.authenticate(reason: "Voir tes photos de progression") }
        }
    }
}
