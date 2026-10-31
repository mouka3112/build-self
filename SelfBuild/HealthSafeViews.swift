import SwiftUI
import Combine

// MARK: - Santé + rapport médecin (PDF)
enum HealthReport {
    @MainActor
    static func make(store: AppStore, days: Int) -> URL? {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -days, to: .now) ?? .now
        let entries = store.healthLog.filter { $0.date >= start }.sorted { $0.date < $1.date }
        let fmt = DateFormatter(); fmt.dateFormat = "dd/MM HH:mm"
        let st = store.stats(days: max(days, 1))
        var lines = ["RAPPORT SANTÉ – Melik", "Période : \(days) derniers jours (généré le \(fmt.string(from: .now)))",
                     "Journal personnel, pas un diagnostic.", "",
                     "Résumé : calories moy. \(Int(st.avgKcal)) kcal/j, protéines moy. \(Int(st.avgProtein)) g/j, séances de sport \(st.sessions), hygiène \(Int(st.hygienePct * 100))%.", "",
                     "Entrées :"]
        lines += entries.map { "\(fmt.string(from: $0.date))  [\($0.kind)]  \($0.text)" }
        if entries.isEmpty { lines.append("Aucune entrée.") }

        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Rapport-sante.pdf")
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11)]
        do {
            try UIGraphicsPDFRenderer(bounds: page).writePDF(to: url) { ctx in
                var y: CGFloat = 40
                ctx.beginPage()
                for l in lines {
                    let h = (l as NSString).boundingRect(with: CGSize(width: 515, height: Double.greatestFiniteMagnitude),
                                                         options: .usesLineFragmentOrigin, attributes: attrs, context: nil).height
                    if y + h > 800 { ctx.beginPage(); y = 40 }
                    (l as NSString).draw(in: CGRect(x: 40, y: y, width: 515, height: h), withAttributes: attrs)
                    y += h + 4
                }
            }
            return url
        } catch { return nil }
    }
}

struct HealthView: View {
    @EnvironmentObject var store: AppStore
    @State private var kind = "Symptôme"
    @State private var text = ""
    @State private var reportURL: URL?
    private let kinds = ["Symptôme", "Médicament", "Sommeil", "Énergie", "Autre"]

    private var waterToday: Int {
        store.healthLog.filter { $0.kind == "Eau" && Calendar.current.isDateInToday($0.date) }.count * 250
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("💧 \(waterToday) ml").font(.title2.bold()); Text("eau aujourd'hui (objectif ≈ 2 L)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { store.healthLog.append(HealthEntry(date: .now, kind: "Eau", text: "250 ml")); Haptic.tap() } label: {
                            Text("+250 ml").font(.headline).padding(.horizontal, 16).padding(.vertical, 10).glassCard(18)
                        }.buttonStyle(PressStyle())
                    }
                    .padding(16).glassCard(24)

                    VStack(spacing: 10) {
                        Picker("Type", selection: $kind) { ForEach(kinds, id: \.self) { Text($0) } }.pickerStyle(.menu)
                        HStack(alignment: .top) {
                            TextField(kind == "Sommeil" ? "Ex : 8 h 30, réveil facile" : kind == "Énergie" ? "Ex : 4/5" : "Détails (heure, intensité, dosage…)", text: $text, axis: .vertical).lineLimit(1...4)
                            DictationButton(text: $text)
                        }.padding(12).glassCard(14)
                        Button {
                            guard !text.isEmpty else { return }
                            store.healthLog.append(HealthEntry(date: .now, kind: kind, text: text)); text = ""; Haptic.success()
                        } label: { Label("Ajouter au journal", systemImage: "plus") }.buttonStyle(GlassButtonStyle(prominent: true))
                    }
                    .padding(16).glassCard(24)

                    VStack(spacing: 10) {
                        Button { reportURL = HealthReport.make(store: store, days: 30) } label: { Label("Générer le rapport médecin (30 j)", systemImage: "doc.richtext") }
                            .buttonStyle(GlassButtonStyle())
                        if let u = reportURL {
                            ShareLink(item: u) { Label("Partager / imprimer le PDF", systemImage: "square.and.arrow.up") }.buttonStyle(GlassButtonStyle(prominent: true))
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Aujourd'hui").font(.headline)
                        let today = store.healthLog.filter { Calendar.current.isDateInToday($0.date) && $0.kind != "Eau" }
                        if today.isEmpty { Text("Rien noté pour le moment.").font(.caption).foregroundStyle(.secondary) }
                        ForEach(today.reversed()) { e in
                            HStack(alignment: .top) {
                                Text(e.date, format: .dateTime.hour().minute()).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                Text("\(e.kind) – \(e.text)")
                                Spacer()
                            }
                            .contextMenu { Button("Supprimer", role: .destructive) { store.healthLog.removeAll { $0.id == e.id } } }
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard(24)

                    Text("Ce journal ne remplace pas un médecin. En cas de symptôme inquiétant, parles-en à tes parents ou à un médecin.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Santé")
    }
}

// MARK: - Safe Space (Face ID, stockage local protégé)
final class SafeStore: ObservableObject {
    @Published var entries: [SafeEntry] = []
    private var url: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("safe.json") }

    func load() {
        guard let d = try? Data(contentsOf: url), let e = try? JSONDecoder().decode([SafeEntry].self, from: d) else { return }
        entries = e
    }
    func save() {
        guard let d = try? JSONEncoder().encode(entries) else { return }
        try? d.write(to: url, options: [.atomic, .completeFileProtection])
    }
    func clear() { entries = []; try? FileManager.default.removeItem(at: url) }
}

private struct MoodResult: Decodable { let mood: Int; let label: String; let advice: String }

struct SafeSpaceView: View {
    @EnvironmentObject var gemini: GeminiClient
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var safe = SafeStore()
    @State private var unlocked = false
    @State private var text = ""
    @State private var busy = false
    @State private var confirmAI: SafeEntry?

    var body: some View {
        ZStack {
            AppBackground()
            if unlocked { content } else {
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 54))
                    Text("Safe Space").font(.title.bold())
                    Text("Ton journal privé, protégé par Face ID.").foregroundStyle(.secondary)
                    Button("Déverrouiller") { unlock() }.buttonStyle(GlassButtonStyle(prominent: true)).padding(.horizontal, 60)
                }
            }
        }
        .navigationTitle("Safe Space")
        .task { unlock() }
        .onChange(of: scenePhase) { _, p in if p != .active { unlocked = false; safe.entries = []; text = "" } }
        .alert("Analyser avec l'IA ?", isPresented: Binding(get: { confirmAI != nil }, set: { if !$0 { confirmAI = nil } })) {
            Button("Analyser") { if let e = confirmAI { analyze(e) }; confirmAI = nil }
            Button("Non, garder privé", role: .cancel) { confirmAI = nil }
        } message: { Text("Le texte de cette entrée sera envoyé à Gemini (Google) pour estimer ton humeur. Rien n'est envoyé sans ton accord.") }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 10) {
                    HStack(alignment: .top) {
                        TextField("Écris ou dicte ce que tu ressens…", text: $text, axis: .vertical).lineLimit(4...10)
                        DictationButton(text: $text)
                    }.padding(12).glassCard(18)
                    Button { add() } label: { Label("Enregistrer", systemImage: "lock.fill") }
                        .buttonStyle(GlassButtonStyle(prominent: true)).disabled(text.isEmpty)
                }
                .padding(16).glassCard(24)

                if busy { ProgressView("Nexus lit avec bienveillance…") }

                ForEach(safe.entries.sorted { $0.date > $1.date }) { e in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(e.date, format: .dateTime.day().month(.abbreviated).hour().minute()).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if let m = e.mood { Text("\(moodEmoji(m)) \(e.moodLabel ?? "") \(m)/10").font(.caption.weight(.semibold)) }
                        }
                        Text(e.text)
                        if let a = e.advice { Text(a).font(.footnote).foregroundStyle(.secondary).padding(10).glassCard(14) }
                        if e.mood == nil {
                            Button { confirmAI = e } label: { Label("Analyser mon humeur", systemImage: "sparkles").font(.caption.weight(.semibold)) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16).glassCard(22)
                    .contextMenu { Button("Supprimer", role: .destructive) { safe.entries.removeAll { $0.id == e.id }; safe.save() } }
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func moodEmoji(_ m: Int) -> String { m >= 8 ? "😄" : m >= 6 ? "🙂" : m >= 4 ? "😐" : "😔" }

    private func unlock() {
        Task {
            if await Biometrics.authenticate(reason: "Ouvrir ton Safe Space") { safe.load(); unlocked = true }
        }
    }

    private func add() {
        safe.entries.append(SafeEntry(date: .now, text: text)); safe.save(); text = ""; Haptic.success()
    }

    private func analyze(_ e: SafeEntry) {
        busy = true
        Task {
            do {
                let r = try await gemini.json(MoodResult.self, """
                Voici une entrée de journal intime de Melik, 15 ans : « \(e.text) »
                Estime son humeur et réponds avec bienveillance. JSON uniquement : {"mood": entier 1 à 10, "label": "un mot", "advice": "2 phrases chaleureuses et un petit conseil concret"}
                Si tu perçois une détresse sérieuse, encourage-le avec douceur à en parler à un adulte de confiance (parent, conseiller du lycée, médecin).
                """)
                if let i = safe.entries.firstIndex(where: { $0.id == e.id }) {
                    safe.entries[i].mood = r.mood; safe.entries[i].moodLabel = r.label; safe.entries[i].advice = r.advice; safe.save()
                }
            } catch {}
            busy = false
        }
    }
}