import SwiftUI

struct MealItem: Decodable { let name: String; let grams: Double; let kcal: Double; let protein: Double }
struct MealResult: Decodable { let items: [MealItem] }
struct FoodEstimate: Decodable { let kcal100: Double; let protein100: Double; let portion: Double }

struct NutritionView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var gemini: GeminiClient
    @State private var showPicker = false
    @State private var showAdd = false
    @State private var analyzing = false
    @State private var message = ""
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 14) {
                            GaugeBar(title: "Calories", value: store.kcalToday, goal: store.calorieGoal, unit: "kcal")
                            GaugeBar(title: "Protéines", value: store.proteinToday, goal: store.proteinGoal, unit: "g")
                        }
                        .padding(16).glassCard(24)

                        Button { showPicker = true } label: { Label("Photo de mon repas", systemImage: "camera.fill") }
                            .buttonStyle(GlassButtonStyle()).disabled(analyzing)
                        if analyzing { ProgressView("Nexus analyse ton repas…") }
                        if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }

                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(store.allFoodCards) { card in
                                Button {
                                    store.addFood(card, grams: card.portion)
                                    message = "+\(Int(card.portion)) g de \(card.name) (\(Int(card.kcal100 * card.portion / 100)) kcal, \(Int(card.protein100 * card.portion / 100)) g prot.)"
                                    Haptic.tap()
                                } label: {
                                    VStack(spacing: 6) {
                                        Text(card.emoji).font(.system(size: 40))
                                        Text(card.name).font(.headline).multilineTextAlignment(.center)
                                        Text("+\(Int(card.portion)) g").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 18).glassCard(24)
                                }
                                .buttonStyle(PressStyle())
                                .contextMenu {
                                    ForEach([50, 100, 150, 200, 300], id: \.self) { g in
                                        Button("+\(g) g") { store.addFood(card, grams: Double(g)) }
                                    }
                                    if card.id.hasPrefix("custom-") {
                                        Button("Supprimer la carte", role: .destructive) { store.engine.apply(.delete(.customFood(card.id))) }
                                    }
                                }
                            }
                            Button { showAdd = true } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill").font(.system(size: 40))
                                    Text("Autre").font(.headline)
                                    Text("Nouvel ingrédient").font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 18).glassCard(24)
                            }.buttonStyle(PressStyle())
                        }
                        Text("Appui long sur une carte pour une autre portion.").font(.caption).foregroundStyle(.secondary)

                        if !store.todayFoods.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Aujourd'hui").font(.headline)
                                ForEach(store.todayFoods.reversed()) { f in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(f.name); Text("\(Int(f.grams)) g").font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text("\(Int(f.kcal)) kcal · \(Int(f.protein)) g P").font(.caption.monospacedDigit())
                                        Button { store.engine.apply(.delete(.food(f.id))) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 32, height: 32) }
                                    }
                                }
                            }
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard(24)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Nutrition")
        }
        .hideKeyboardOnTap()
        .photoPicker(isPresented: $showPicker) { analyze($0) }
        .sheet(isPresented: $showAdd) { AddFoodSheet() }
    }

    private func analyze(_ image: UIImage) {
        analyzing = true; message = ""
        Task {
            do {
                let r = try await gemini.json(MealResult.self, """
                Analyse cette photo de repas. Liste chaque aliment visible avec une estimation réaliste, TOTAUX pour la portion visible.
                Réponds UNIQUEMENT en JSON : {"items":[{"name":"nom court en français","grams":nombre,"kcal":nombre,"protein":nombre}]}
                """, image: image)
                let lines = r.items.filter { !$0.name.isEmpty && $0.grams > 0 }
                    .map { MealLine(name: $0.name, grams: $0.grams, kcal: $0.kcal, protein: $0.protein) }
                let res = store.engine.apply(.meal(items: lines))
                message = res.summary + (res.status == .applied ? " — estimation approximative." : "")
                if res.status == .applied { Haptic.success() } else { Haptic.warn() }
            } catch { message = error.localizedDescription }
            analyzing = false
        }
    }
}

struct AddFoodSheet: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var gemini: GeminiClient
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var grams = "100"
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Ingrédient") {
                    TextField("Nom (ex : thon, avocat…)", text: $name)
                    Button { estimate() } label: { Label(busy ? "Nexus calcule…" : "Estimer avec Nexus", systemImage: "sparkles") }
                        .disabled(name.isEmpty || busy)
                    if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.secondary) }
                }
                Section("Pour 100 g") {
                    TextField("Calories (kcal)", text: $kcal).keyboardType(.decimalPad)
                    TextField("Protéines (g)", text: $protein).keyboardType(.decimalPad)
                }
                Section("Portion mangée") { TextField("Grammes", text: $grams).keyboardType(.decimalPad) }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Autre ingrédient")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") { add() }.disabled(name.isEmpty) }
            }
        }
        .hideKeyboardOnTap()
    }

    private func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    private func add() {
        store.addCustomFood(name: name, grams: max(num(grams), 1), kcal100: num(kcal), protein100: num(protein))
        Haptic.success(); dismiss()
    }

    private func estimate() {
        busy = true; error = ""
        Task {
            do {
                let r = try await gemini.json(FoodEstimate.self, """
                Pour l'aliment « \(name) » (prêt à manger), donne les valeurs moyennes pour 100 g.
                JSON uniquement : {"kcal100": nombre, "protein100": nombre, "portion": portion typique en grammes}
                """)
                kcal = String(Int(r.kcal100)); protein = String(format: "%.1f", r.protein100); grams = String(Int(r.portion))
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
