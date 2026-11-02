import SwiftUI
import UIKit

/// Premier lancement : clé Gemini → profil → objectifs → rythme (besoins calculés puis modifiables).
struct OnboardingView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var gemini: GeminiClient
    @AppStorage("geminiKey") private var key = ""
    @State private var step = 0
    @State private var p = UserProfile()
    @State private var keyStatus = ""
    @State private var keyOK = false
    @State private var testing = false
    @State private var cityStatus = ""
    @State private var customGoal = ""
    @State private var customSubject = ""
    @State private var kcal = 2600.0
    @State private var protein = 120.0
    @State private var wake = Fmt.dateAt(minute: 7 * 60)
    @State private var bed = Fmt.dateAt(minute: 22 * 60)

    private let currencies = ["TND", "EUR", "USD", "MAD", "DZD", "CAD", "CHF"]

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch step {
                        case 0: keyStep
                        case 1: profileStep
                        case 2: goalsStep
                        default: rhythmStep
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                footer
            }
        }
        .hideKeyboardOnTap()
        .preferredColorScheme(.dark)
        .onAppear(perform: prefill)
    }

    // MARK: En-tête / pied
    private var header: some View {
        VStack(spacing: 8) {
            MascotView(thinking: testing, size: 64)
            Text(["Ta clé IA", "Ton profil", "Tes objectifs", "Ton rythme"][min(step, 3)])
                .font(.system(.title, design: .rounded).weight(.bold))
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(i <= step ? Color.white : Color.white.opacity(0.2)).frame(width: i == step ? 28 : 12, height: 6)
                }
            }
        }
        .padding(.top, 12)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if step > 0 {
                Button { withAnimation { step -= 1 } } label: { Text("Retour") }
                    .buttonStyle(GlassButtonStyle()).frame(width: 120)
            }
            Button {
                withAnimation {
                    if step == 2 { recompute() }
                    if step < 3 { step += 1 } else { finish() }
                }
            } label: { Text(step < 3 ? "Continuer" : "C'est parti 🚀") }
                .buttonStyle(GlassButtonStyle(prominent: true))
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.5)
        }
        .padding()
    }

    private var canContinue: Bool {
        switch step {
        case 0: return !key.trimmingCharacters(in: .whitespaces).isEmpty
        case 1: return !p.firstName.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }

    // MARK: Étape 1 – clé Gemini
    private var keyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nexus, ton coach IA, utilise Google Gemini. La clé est **gratuite** :")
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Ouvre Google AI Studio (bouton ci-dessous) et connecte-toi avec un compte Google.")
                Text("2. Appuie sur « Create API key » puis copie la clé (elle commence par AIza…).")
                Text("3. Reviens ici, appuie sur « Coller » puis « Tester la clé ».")
            }
            .font(.callout).foregroundStyle(.secondary)
            Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                Label("Ouvrir Google AI Studio", systemImage: "safari")
            }
            .buttonStyle(GlassButtonStyle())
            SecureField("Clé API Gemini", text: $key)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(14).glassCard(18)
            HStack(spacing: 10) {
                Button {
                    if let s = UIPasteboard.general.string { key = s.trimmingCharacters(in: .whitespacesAndNewlines) }
                } label: { Label("Coller", systemImage: "doc.on.clipboard") }
                    .buttonStyle(GlassButtonStyle())
                Button { testKey() } label: { Label(testing ? "Test…" : "Tester la clé", systemImage: "checkmark.shield") }
                    .buttonStyle(GlassButtonStyle(prominent: true))
                    .disabled(testing || key.isEmpty)
            }
            if !keyStatus.isEmpty {
                Text(keyStatus).font(.footnote)
                    .foregroundStyle(keyOK ? Color(red: 0.42, green: 0.86, blue: 0.5) : Color(red: 1.0, green: 0.55, blue: 0.4))
            }
            Text("La clé reste uniquement sur ton iPhone. Tu pourras la changer dans Plus → Réglages.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Étape 2 – profil
    private var profileStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Prénom") { TextField("Ton prénom", text: $p.firstName).textInputAutocapitalization(.words) }
            HStack(spacing: 10) {
                field("Âge") { Stepper("\(p.age) ans", value: $p.age, in: 10...80) }
            }
            field("Taille") { Stepper("\(Int(p.heightCm)) cm", value: $p.heightCm, in: 120...220, step: 1) }
            field("Poids") { Stepper("\(fmtKg(p.weightKg)) kg", value: $p.weightKg, in: 30...160, step: 0.5) }
            field("Sexe (pour le calcul des besoins)") {
                Picker("Sexe", selection: $p.sex) { Text("Garçon").tag("M"); Text("Fille").tag("F") }.pickerStyle(.segmented)
            }
            field("Ville (la météo suit ta ville)") {
                HStack {
                    TextField("Ex : Le Kef", text: $p.city).textInputAutocapitalization(.words)
                    Button("Vérifier") { checkCity() }.font(.callout.weight(.semibold))
                }
            }
            if !cityStatus.isEmpty { Text(cityStatus).font(.caption).foregroundStyle(.secondary) }
            field("Monnaie") {
                Picker("Monnaie", selection: $p.currency) { ForEach(currencies, id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu)
            }
            Toggle("Je suis élève", isOn: $p.isStudent).padding(14).glassCard(18)
            if p.isStudent {
                field("Niveau") { TextField("Ex : 1ère année secondaire", text: $p.level) }
                field("Établissement") { TextField("Ex : Lycée pilote du Kef", text: $p.school) }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Matières").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ChipGrid(items: schoolSubjects + p.subjects.filter { !schoolSubjects.contains($0) }, selected: $p.subjects)
                    HStack {
                        TextField("Autre matière", text: $customSubject)
                        Button("Ajouter") {
                            let s = customSubject.trimmingCharacters(in: .whitespaces)
                            if !s.isEmpty && !p.subjects.contains(s) { p.subjects.append(s) }
                            customSubject = ""
                        }
                    }
                    .padding(12).glassCard(16)
                }
            }
        }
    }

    // MARK: Étape 3 – objectifs
    private var goalsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choisis ce qui compte pour toi. Nexus s'en sert pour tes plannings et ses conseils.").foregroundStyle(.secondary)
            ChipGrid(items: UserProfile.goalChoices + p.goals.filter { !UserProfile.goalChoices.contains($0) }, selected: $p.goals)
            HStack {
                TextField("Autre objectif", text: $customGoal)
                Button("Ajouter") {
                    let g = customGoal.trimmingCharacters(in: .whitespaces)
                    if !g.isEmpty && !p.goals.contains(g) { p.goals.append(g) }
                    customGoal = ""
                }
            }
            .padding(12).glassCard(16)
            field("En une phrase, ce que tu veux devenir (optionnel)") {
                TextField("Ex : être discipliné et fort d'ici l'été", text: $p.goalsNote, axis: .vertical).lineLimit(1...3)
            }
            if p.age < 18 {
                Label("Pour un ado : pas de régime extrême, pas de produits dopants, charges prudentes, 8-9 h de sommeil.", systemImage: "heart.text.square")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Étape 4 – rythme
    private var rhythmStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Réveil") { DatePicker("Heure de réveil", selection: $wake, displayedComponents: .hourAndMinute) }
            field("Coucher") { DatePicker("Heure de coucher", selection: $bed, displayedComponents: .hourAndMinute) }
            let sleepH = Double((Fmt.minutesOf(wake) + 1440 - Fmt.minutesOf(bed)) % 1440) / 60
            Text(String(format: "Sommeil prévu : %.1f h", sleepH) + (sleepH < 8 && p.age < 18 ? " — vise plutôt 8 à 9 h 😴" : ""))
                .font(.caption).foregroundStyle(.secondary)
            field("Calories par jour (calculées, modifiables)") {
                Stepper("\(Int(kcal)) kcal", value: $kcal, in: 1500...5000, step: 50)
            }
            field("Protéines par jour") {
                Stepper("\(Int(protein)) g", value: $protein, in: 40...250, step: 5)
            }
            Button("Recalculer depuis mon profil") { recompute() }.font(.callout.weight(.semibold))
            Text("Estimation (formule Mifflin-St Jeor × activité) : c'est une base, pas une prescription médicale.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func field<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content().padding(12).glassCard(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Logique
    private func prefill() {
        if let existing = store.profile { p = existing }
        kcal = store.calorieGoal
        protein = store.proteinGoal
        wake = Fmt.dateAt(minute: p.wakeMinute)
        bed = Fmt.dateAt(minute: p.bedMinute)
        if !key.isEmpty { keyStatus = "Une clé est déjà enregistrée. Tu peux la tester." }
    }

    private func testKey() {
        testing = true
        Task {
            let r = await gemini.testKey(key)
            keyOK = r.ok
            keyStatus = r.message
            testing = false
            if r.ok { Haptic.success() } else { Haptic.warn() }
        }
    }

    private func checkCity() {
        cityStatus = "Recherche…"
        Task {
            if let c = await WeatherService.geocode(p.city) {
                p.cityLabel = c.label; p.latitude = c.lat; p.longitude = c.lon
                cityStatus = "📍 \(c.label)"
            } else {
                cityStatus = "Ville introuvable : vérifie l'orthographe (la météo restera sur Le Kef)."
            }
        }
    }

    private func recompute() {
        kcal = p.suggestedCalories
        protein = p.suggestedProtein
    }

    private func finish() {
        p.wakeMinute = Fmt.minutesOf(wake)
        p.bedMinute = Fmt.minutesOf(bed)
        if p.cityLabel.isEmpty || !p.cityLabel.lowercased().contains(p.city.lowercased()) {
            Task {
                if let c = await WeatherService.geocode(p.city) {
                    var q = p
                    q.cityLabel = c.label; q.latitude = c.lat; q.longitude = c.lon
                    store.profile = q
                }
            }
        }
        store.completeOnboarding(p, kcal: kcal, protein: protein)
        Haptic.success()
    }
}

/// Puces sélectionnables (matières, objectifs).
struct ChipGrid: View {
    let items: [String]
    @Binding var selected: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                let on = selected.contains(item)
                Button {
                    if on { selected.removeAll { $0 == item } } else { selected.append(item) }
                    Haptic.tap()
                } label: {
                    Text(item).font(.callout.weight(on ? .semibold : .regular))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.vertical, 10).padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(on ? Color.black : Color.white)
                        .background { if on { Capsule().fill(Color.white) } }
                        .modifier(ChipGlass(enabled: !on))
                }
                .buttonStyle(PressStyle())
            }
        }
    }
}

private struct ChipGlass: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.glassCard(22) } else { content }
    }
}
