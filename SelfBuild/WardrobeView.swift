import SwiftUI

struct WardrobeView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var gemini: GeminiClient
    @State private var weather: Weather?
    @State private var suggestion = ""
    @State private var loading = false
    @State private var name = ""
    @State private var category = "Haut"
    private let categories = ["Haut", "Bas", "Veste", "Chaussures", "Autre"]

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 16) {
                    weatherCard
                    VStack(spacing: 10) {
                        Picker("Catégorie", selection: $category) { ForEach(categories, id: \.self) { Text($0) } }.pickerStyle(.segmented)
                        HStack {
                            TextField("Nom de l'habit (ex : hoodie noir)", text: $name).padding(12).glassCard(14)
                            Button {
                                guard !name.isEmpty else { return }
                                store.wardrobe.append(ClothingItem(name: name, category: category)); name = ""
                            } label: { Image(systemName: "plus.circle.fill").font(.title) }
                        }
                    }
                    .padding(16).glassCard(24)

                    ForEach(categories, id: \.self) { cat in
                        let items = store.wardrobe.filter { $0.category == cat }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(cat).font(.headline)
                                ForEach(items) { it in
                                    HStack {
                                        Text(it.name)
                                        Spacer()
                                        Button { toggle(it) } label: {
                                            Text(it.clean ? "Propre" : "Sale").font(.caption.weight(.semibold))
                                                .padding(.horizontal, 12).padding(.vertical, 6)
                                                .foregroundStyle(it.clean ? Color.black : Color.white)
                                                .background { if it.clean { Capsule().fill(Color.white) } }
                                                .overlay { if !it.clean { Capsule().stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3])) } }
                                        }
                                    }
                                    .contextMenu { Button("Supprimer", role: .destructive) { store.wardrobe.removeAll { $0.id == it.id } } }
                                }
                            }
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard(24)
                        }
                    }
                    if store.wardrobe.contains(where: { !$0.clean }) {
                        Button("Tout est lavé ✅") { for i in store.wardrobe.indices { store.wardrobe[i].clean = true } }
                            .buttonStyle(GlassButtonStyle())
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Garde-robe")
        .task { weather = await WeatherService.fetch() }
    }

    private var weatherCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: weather?.icon ?? "cloud.fill").font(.largeTitle)
                VStack(alignment: .leading) {
                    Text(weather.map { "\(Int($0.temp.rounded()))°C – \($0.summary)" } ?? "Météo indisponible").font(.headline)
                    Text("Le Kef").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Button { suggest() } label: { Label(loading ? "Nexus choisit…" : "Quelle tenue aujourd'hui ?", systemImage: "sparkles") }
                .buttonStyle(GlassButtonStyle(prominent: true)).disabled(loading)
            if !suggestion.isEmpty { Text(suggestion).font(.callout) }
        }
        .padding(16).glassCard(24)
    }

    private func toggle(_ it: ClothingItem) {
        if let i = store.wardrobe.firstIndex(where: { $0.id == it.id }) { store.wardrobe[i].clean.toggle() }
    }

    private func suggest() {
        let clean = store.wardrobe.filter { $0.clean }.map { "\($0.category) : \($0.name)" }.joined(separator: " ; ")
        guard !clean.isEmpty else { suggestion = "Ajoute d'abord tes habits (propres) ci-dessus."; return }
        let w = weather.map { "\(Int($0.temp.rounded()))°C, \($0.summary)" } ?? "météo inconnue"
        loading = true
        Task {
            do {
                suggestion = try await gemini.text("""
                Météo au Kef : \(w). Habits PROPRES disponibles : \(clean).
                Propose UNE tenue complète pour aujourd'hui en utilisant uniquement ces habits, adaptée à un lycéen. 3 lignes max, avec une courte raison.
                """, store: store)
            } catch { suggestion = error.localizedDescription }
            loading = false
        }
    }
}
