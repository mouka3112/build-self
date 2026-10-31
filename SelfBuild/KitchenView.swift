import SwiftUI

struct DishRating: Decodable { let score: Int; let comment: String; let updatedProfile: String }

struct KitchenView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var gemini: GeminiClient
    @State private var recipe = ""
    @State private var busy = false
    @State private var dishName = ""
    @State private var liked = true
    @State private var showPicker = false
    @State private var result = ""

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ce que j'ai en stock").font(.headline)
                        HStack(alignment: .top) {
                            TextField("Ex : riz, œufs, tomates, thon, fromage…", text: $store.kitchenStock, axis: .vertical).lineLimit(2...6)
                            DictationButton(text: $store.kitchenStock)
                        }
                        .padding(12).glassCard(18)
                        Button { generate() } label: { Label(busy ? "Nexus cuisine…" : "Générer une recette", systemImage: "sparkles") }
                            .buttonStyle(GlassButtonStyle(prominent: true)).disabled(busy || store.kitchenStock.isEmpty)
                        if !recipe.isEmpty { Text(recipe).font(.callout) }
                    }
                    .padding(16).glassCard(24)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("J'ai cuisiné !").font(.headline)
                        TextField("Nom du plat", text: $dishName).padding(12).glassCard(14)
                        Picker("Goût", selection: $liked) {
                            Text("👍 J'ai aimé").tag(true); Text("👎 Moyen").tag(false)
                        }.pickerStyle(.segmented)
                        Button { showPicker = true } label: { Label("Photo du plat → note de Nexus", systemImage: "camera.fill") }
                            .buttonStyle(GlassButtonStyle()).disabled(busy)
                        if !result.isEmpty { Text(result).font(.callout) }
                    }
                    .padding(16).glassCard(24)

                    if !store.tasteProfile.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Mes goûts (appris par Nexus)").font(.headline)
                            Text(store.tasteProfile).font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard(24)
                    }

                    if !store.dishes.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Mes plats").font(.headline)
                            ForEach(store.dishes.sorted { $0.date > $1.date }.prefix(10)) { d in
                                HStack(spacing: 12) {
                                    if let f = d.photo, let img = PhotoStore.load(f) {
                                        Image(uiImage: img).resizable().scaledToFill().frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                    VStack(alignment: .leading) {
                                        Text(d.name).font(.headline)
                                        Text(d.comment).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer()
                                    Text("\(d.score)/10").font(.headline.monospacedDigit())
                                }
                            }
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard(24)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Cuisine")
        .photoPicker(isPresented: $showPicker) { rate($0) }
    }

    private func generate() {
        busy = true
        Task {
            do {
                recipe = try await gemini.text("""
                Stock disponible : \(store.kitchenStock).
                Goûts connus : \(store.tasteProfile.isEmpty ? "inconnus" : store.tasteProfile).
                Propose UNE recette simple pour un débutant de 15 ans qui veut manger riche en protéines (objectif ≈ \(Int(store.proteinGoal)) g/jour).
                Format : nom, ingrédients (parmi le stock, tu peux ajouter 2-3 basiques), étapes courtes numérotées, temps, calories et protéines estimées. Max 170 mots.
                """, store: store)
            } catch { recipe = error.localizedDescription }
            busy = false
        }
    }

    private func rate(_ img: UIImage) {
        busy = true; result = ""
        let name = dishName.isEmpty ? "Plat maison" : dishName
        Task {
            do {
                let r = try await gemini.json(DishRating.self, """
                Photo du plat que Melik (15 ans) vient de préparer : « \(name) ». Il dit l'avoir \(liked ? "aimé" : "peu aimé").
                Profil de goûts actuel : \(store.tasteProfile.isEmpty ? "inconnu" : store.tasteProfile)
                JSON uniquement : {"score": note sur 10 (présentation + équilibre apparent), "comment": "2 phrases d'encouragement + 1 conseil concret", "updatedProfile": "profil de goûts mis à jour, 3 phrases max"}
                """, image: img, store: store)
                store.dishes.append(DishLog(date: .now, name: name, score: r.score, comment: r.comment, liked: liked, photo: PhotoStore.save(img)))
                store.tasteProfile = r.updatedProfile
                result = "\(r.score)/10 – \(r.comment)"
                Haptic.success()
            } catch { result = error.localizedDescription }
            busy = false
        }
    }
}
