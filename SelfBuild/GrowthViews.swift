import SwiftUI

private struct StepsResponse: Decodable { let steps: [String] }
private struct ChallengesResponse: Decodable { let challenges: [String] }

// MARK: - Projets + roadmap IA
struct ProjectsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var gemini: GeminiClient
    @State private var title = ""
    @State private var goal = ""
    @State private var busyID: UUID?
    @State private var error = ""

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        TextField("Nom du projet", text: $title).padding(12).glassCard(14)
                        HStack(alignment: .top) {
                            TextField("Objectif / où tu veux arriver", text: $goal, axis: .vertical).lineLimit(1...4)
                            DictationButton(text: $goal)
                        }.padding(12).glassCard(14)
                        Button {
                            guard !title.isEmpty else { return }
                            store.engine.apply(.add(.project(Project(title: title, goal: goal)))); title = ""; goal = ""
                        } label: { Label("Créer le projet", systemImage: "plus") }.buttonStyle(GlassButtonStyle(prominent: true))
                    }
                    .padding(16).glassCard(24)
                    if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.secondary) }

                    ForEach(store.projects) { p in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(p.title).font(.headline)
                                Spacer()
                                if !p.steps.isEmpty {
                                    Text("\(p.steps.filter { $0.done }.count)/\(p.steps.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                            if !p.goal.isEmpty { Text(p.goal).font(.caption).foregroundStyle(.secondary) }
                            ForEach(p.steps) { s in
                                Button { toggleStep(p, s); Haptic.tap() } label: {
                                    HStack(alignment: .top) {
                                        Image(systemName: s.done ? "checkmark.circle.fill" : "circle")
                                        Text(s.title).strikethrough(s.done).multilineTextAlignment(.leading)
                                        Spacer()
                                    }.opacity(s.done ? 0.5 : 1)
                                }.buttonStyle(.plain)
                            }
                            Button { roadmap(for: p) } label: {
                                Label(busyID == p.id ? "Nexus planifie…" : (p.steps.isEmpty ? "Générer la roadmap" : "Régénérer la roadmap"), systemImage: "sparkles")
                            }.buttonStyle(GlassButtonStyle()).disabled(busyID != nil)
                        }
                        .padding(16).glassCard(24)
                        .contextMenu { Button("Supprimer", role: .destructive) { store.engine.apply(.delete(.project(p.id))) } }
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Projets")
    }

    private func toggleStep(_ p: Project, _ s: RoadmapStep) {
        guard var q = store.projects.first(where: { $0.id == p.id }), let i = q.steps.firstIndex(where: { $0.id == s.id }) else { return }
        q.steps[i].done.toggle()
        store.engine.apply(.update(.project(q)))
    }

    private func roadmap(for p: Project) {
        busyID = p.id; error = ""
        Task {
            do {
                let r = try await gemini.json(StepsResponse.self, """
                Projet de \(store.aiPersona) : « \(p.title) ». Objectif : \(p.goal.isEmpty ? "non précisé" : p.goal).
                Crée une roadmap réaliste de 6 à 10 étapes concrètes, ordonnées, réalisables avec un emploi du temps de lycéen.
                JSON uniquement : {"steps": ["étape 1", "étape 2", …]}
                """, store: store)
                if var q = store.projects.first(where: { $0.id == p.id }) {
                    q.steps = r.steps.map { RoadmapStep(title: $0) }
                    store.engine.apply(.update(.project(q)))
                }
            } catch { self.error = error.localizedDescription }
            busyID = nil
        }
    }
}

// MARK: - Micro-défis (gamification)
struct ChallengesView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var gemini: GeminiClient
    @State private var busy = false
    @State private var error = ""

    private var xp: Int { store.challenges.filter { $0.done }.count * 10 }
    private var streak: Int {
        var n = 0; var d = Date()
        func has(_ d: Date) -> Bool { store.challenges.contains { $0.done && Calendar.current.isDate($0.date, inSameDayAs: d) } }
        if !has(d) { d = Calendar.current.date(byAdding: .day, value: -1, to: d) ?? d }
        while has(d) { n += 1; d = Calendar.current.date(byAdding: .day, value: -1, to: d) ?? d; if n > 365 { break } }
        return n
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        VStack { Text("Niv. \(xp / 100 + 1)").font(.title2.bold()); Text("\(xp) XP").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
                        VStack { Text("🔥 \(streak)").font(.title2.bold()); Text("jours d'affilée").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
                    }
                    .padding(16).glassCard(24)

                    if store.challengesToday.isEmpty {
                        Button { generate() } label: { Label(busy ? "Nexus invente…" : "Mes défis du jour", systemImage: "sparkles") }
                            .buttonStyle(GlassButtonStyle(prominent: true)).disabled(busy)
                    }
                    if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.secondary) }

                    ForEach(store.challengesToday) { c in
                        Button { toggle(c) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: c.done ? "checkmark.circle.fill" : "circle").font(.title2)
                                Text(c.text).multilineTextAlignment(.leading).strikethrough(c.done)
                                Spacer()
                                Text("+10").font(.caption.bold()).foregroundStyle(.secondary)
                            }
                            .opacity(c.done ? 0.55 : 1).padding(16).glassCard(22)
                        }.buttonStyle(PressStyle())
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Micro-défis")
    }

    private func toggle(_ c: Challenge) {
        let r = store.engine.apply(c.done ? .reopenChallenge(id: c.id) : .completeChallenge(ref: c.id.uuidString))
        if r.status == .applied { Haptic.success() }
    }

    private func generate() {
        busy = true; error = ""
        Task {
            do {
                let r = try await gemini.json(ChallengesResponse.self, """
                Génère 3 micro-défis du jour (5 à 15 minutes chacun) pour \(store.aiPersona), pour gamifier ses habitudes : un physique, un mental/études, un hygiène ou discipline. Concrets, mesurables, sans matériel.
                JSON uniquement : {"challenges": ["défi 1", "défi 2", "défi 3"]}
                """, store: store)
                for text in r.challenges.prefix(3) { store.engine.apply(.add(.challenge(Challenge(date: .now, text: text)))) }
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

// MARK: - Capsule temporelle
struct CapsuleView: View {
    @EnvironmentObject var store: AppStore
    @State private var text = ""
    @State private var unlock = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var photo: UIImage?
    @State private var showPicker = false

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        HStack(alignment: .top) {
                            TextField("Message à ton futur toi…", text: $text, axis: .vertical).lineLimit(3...8)
                            DictationButton(text: $text)
                        }.padding(12).glassCard(14)
                        DatePicker("S'ouvre le", selection: $unlock, in: Date().addingTimeInterval(3600)..., displayedComponents: [.date, .hourAndMinute])
                        Button { showPicker = true } label: { Label(photo == nil ? "Ajouter une photo" : "Photo ajoutée ✓", systemImage: "camera.fill") }
                            .buttonStyle(GlassButtonStyle())
                        Button { seal() } label: { Label("Sceller la capsule", systemImage: "lock.fill") }
                            .buttonStyle(GlassButtonStyle(prominent: true)).disabled(text.isEmpty && photo == nil)
                    }
                    .padding(16).glassCard(24)

                    ForEach(store.capsules.sorted { $0.unlock < $1.unlock }) { c in
                        VStack(alignment: .leading, spacing: 8) {
                            if c.unlock > .now {
                                Label("Verrouillée jusqu'au \(c.unlock.formatted(date: .abbreviated, time: .shortened))", systemImage: "lock.fill").font(.headline)
                                Text("Écrite le \(c.created.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Label("Ouverte – écrite le \(c.created.formatted(date: .abbreviated, time: .omitted))", systemImage: "lock.open.fill").font(.headline)
                                if let f = c.photo, let img = PhotoStore.load(f) { Image(uiImage: img).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 14)) }
                                Text(c.text)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16).glassCard(22)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Capsule temporelle")
        .photoPicker(isPresented: $showPicker) { photo = $0 }
    }

    private func seal() {
        let cap = TimeCapsule(created: .now, unlock: unlock, text: text, photo: photo.flatMap { PhotoStore.save($0) })
        let r = store.engine.apply(.add(.capsule(cap)))          // notification programmée par le moteur
        if r.status == .applied { text = ""; photo = nil; Haptic.success() } else { Haptic.warn() }
    }
}
