import SwiftUI

struct PlusView: View {
    private let items: [AppDestination] = [.study, .school, .lessons, .reminders, .hygiene, .finance, .tutors, .wardrobe, .kitchen, .running, .music,
                                           .projects, .challenges, .capsule, .reports, .health, .safe, .notes, .journal, .settings]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(items) { d in
                            NavigationLink { DestinationView(dest: d).hideKeyboardOnTap() } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: d.icon).font(.title2).foregroundStyle(d.color).frame(width: 36)
                                    Text(d.title).font(.headline)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }
                                .padding(18).glassCard(24)
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Plus")
        }
        .hideKeyboardOnTap()
    }
}

// MARK: - Études
struct StudyView: View {
    @EnvironmentObject var store: AppStore
    @State private var showAdd = false
    @State private var lockMinutes = 60

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 16) {
                    NavigationLink { SchoolView().hideKeyboardOnTap() } label: {
                        Label("Emploi du temps & contrôles", systemImage: "calendar").frame(maxWidth: .infinity, alignment: .leading).padding(16).glassCard(22)
                    }.buttonStyle(PressStyle())
                    NavigationLink { LessonsView().hideKeyboardOnTap() } label: {
                        Label("Mes cours en photos", systemImage: "photo.stack.fill").frame(maxWidth: .infinity, alignment: .leading).padding(16).glassCard(22)
                    }.buttonStyle(PressStyle())
                    NavigationLink { TutorsView().hideKeyboardOnTap() } label: {
                        Label("Cours particuliers (دروس خصوصية)", systemImage: "person.2.fill").frame(maxWidth: .infinity, alignment: .leading).padding(16).glassCard(22)
                    }.buttonStyle(PressStyle())

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Mode Lockdown", systemImage: "lock.fill").font(.headline)
                        Text("Plein écran, compte à rebours, bruit d'ambiance. Pour sortir : prouve tes devoirs avec une photo analysée par Nexus.")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("Durée", selection: $lockMinutes) {
                            ForEach([30, 45, 60, 90, 120], id: \.self) { Text("\($0) min").tag($0) }
                        }.pickerStyle(.segmented)
                        Button { startLockdown() } label: { Text("Activer le Lockdown") }
                            .buttonStyle(GlassButtonStyle(prominent: true))
                        Text("Limite iOS : le verrouillage ne s'applique qu'à SELF BUILD. Bloquer les autres apps exige FamilyControls (compte développeur payant).")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(16).glassCard(24)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Devoirs").font(.headline)
                        if store.homework.isEmpty { Text("Aucun devoir. Appuie sur + (ou dis-le à Nexus).").foregroundStyle(.secondary) }
                        ForEach(store.homework.sorted { $0.due < $1.due }) { hw in
                            HStack(spacing: 12) {
                                Button { toggle(hw) } label: { Image(systemName: hw.done ? "checkmark.circle.fill" : "circle").font(.title2) }
                                VStack(alignment: .leading) {
                                    Text(hw.subject).font(.headline).strikethrough(hw.done)
                                    Text(hw.title).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(hw.due, format: .dateTime.day().month(.abbreviated)).font(.caption.monospacedDigit())
                            }
                            .opacity(hw.done ? 0.45 : 1)
                            .contextMenu {
                                Button("Supprimer", role: .destructive) { store.engine.apply(.delete(.homework(hw.id))) }
                            }
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard(24)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Études")
        .toolbar { Button { showAdd = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showAdd) { AddHomeworkSheet() }
    }

    private func toggle(_ hw: Homework) {
        let r = store.engine.apply(hw.done ? .reopenHomework(id: hw.id) : .completeHomework(ref: hw.id.uuidString))
        if r.status == .applied { Haptic.tap() }
    }

    private func startLockdown() {
        store.engine.apply(.setLockdown(minutes: lockMinutes))
        LiveActivityManager.shared.start(mode: "focus", title: "Lockdown", subtitle: "Devoirs d'abord", minutes: lockMinutes)
        if UserDefaults.standard.object(forKey: "autoNoise") as? Bool ?? true { MusicManager.shared.startNoise() }
        Haptic.success()
    }
}

struct AddHomeworkSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var subject = "Maths"
    @State private var title = ""
    @State private var due = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Matière", selection: $subject) { ForEach(store.subjectList, id: \.self) { Text($0) } }
                HStack {
                    TextField("Intitulé (ex : exercices p.45)", text: $title)
                    DictationButton(text: $title)
                }
                DatePicker("Rendu le", selection: $due, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.secondary) }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Nouveau devoir")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        let r = store.engine.apply(.homework(subject: subject, title: title.isEmpty ? "Devoir" : title, due: due))
                        if r.status == .applied { Haptic.success(); dismiss() } else { error = r.summary }
                    }
                }
            }
        }
        .hideKeyboardOnTap()
        .onAppear { if let s = store.subjectList.first, !store.subjectList.contains(subject) { subject = s } }
    }
}

// MARK: - Lockdown
struct LockdownView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var gemini: GeminiClient
    @EnvironmentObject var router: Router
    @State private var showPicker = false
    @State private var checking = false
    @State private var feedback = ""
    @State private var holding = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 20) {
                Image(systemName: holding ? "lock.open.fill" : "lock.fill").font(.system(size: 44))
                    .scaleEffect(holding ? 1.2 : 1)
                    .animation(.easeInOut(duration: 5), value: holding)
                    // Sortie de secours (bug réseau / IA) : maintenir le cadenas 5 secondes.
                    .onLongPressGesture(minimumDuration: 5, perform: { unlock(emergency: true) }, onPressingChanged: { holding = $0 })
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let rem = max(0, Int((store.lockdownEnd ?? ctx.date).timeIntervalSince(ctx.date)))
                    Text(String(format: "%02d:%02d", rem / 60, rem % 60))
                        .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                }
                Text("Concentre-toi, \(store.displayName). Les devoirs d'abord.").foregroundStyle(.secondary)

                if !store.pendingHomework.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.pendingHomework) { hw in
                            HStack { Image(systemName: "circle"); Text("\(hw.subject) – \(hw.title)"); Spacer() }
                        }
                    }
                    .padding(16).glassCard(22)
                }

                if store.pendingHomework.isEmpty {
                    Button { unlock(emergency: false) } label: { Text("Terminer le Lockdown") }.buttonStyle(GlassButtonStyle(prominent: true))
                } else {
                    Button { showPicker = true } label: { Label("Valider mes devoirs en photo", systemImage: "camera.fill") }
                        .buttonStyle(GlassButtonStyle(prominent: true))
                        .disabled(checking)
                }
                if checking { ProgressView("Nexus vérifie…") }
                if !feedback.isEmpty { Text(feedback).multilineTextAlignment(.center).padding(.horizontal) }
                Spacer()
                Text("Sortie de secours : maintiens le cadenas 5 secondes.").font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
            .padding(.top, 30)
        }
        .photoPicker(isPresented: $showPicker) { verify($0) }
    }

    private func verify(_ image: UIImage) {
        let pending = store.pendingHomework
        checking = true; feedback = ""
        Task {
            do {
                let r = try await gemini.validateHomework(image: image, pending: pending, name: store.displayName)
                feedback = r.comment
                if r.valid {
                    for idx in r.validatedIndices where idx >= 1 && idx <= pending.count {
                        store.engine.apply(.completeHomework(ref: pending[idx - 1].id.uuidString))
                    }
                    if store.pendingHomework.isEmpty { Haptic.success(); unlock(emergency: false) }
                } else { Haptic.warn() }
            } catch { feedback = error.localizedDescription }
            checking = false
        }
    }

    private func unlock(emergency: Bool) {
        store.engine.apply(.setLockdown(minutes: nil))
        LiveActivityManager.shared.end(message: emergency ? nil : "Lockdown réussi")
        MusicManager.shared.stopNoise()
        if !emergency {
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                router.wrapUp = WrapUpRequest(kind: "study")
            }
        }
    }
}

// MARK: - Finances
struct FinanceView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var gemini: GeminiClient
    @State private var category: String?
    @State private var custom = ""
    @State private var showIncome = false
    @State private var incomeText = ""
    @State private var showPicker = false
    @State private var scanning = false
    @State private var message = ""
    @State private var showAll = false

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text("Solde disponible").font(.caption).foregroundStyle(.secondary)
                        Text(Fmt.money(store.balance, store.currency)).font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(store.balance < 0 ? Color(red: 1.0, green: 0.55, blue: 0.4) : AppDestination.finance.color)
                        Text("Dépensé ce mois : \(Fmt.money(store.monthSpent, store.currency))").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(20).glassCard(28)

                    NavigationLink { TutorsView().hideKeyboardOnTap() } label: {
                        HStack { Label("Études · Cours particuliers (دروس خصوصية)", systemImage: "graduationcap.fill"); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                            .padding(16).glassCard(22)
                    }.buttonStyle(PressStyle())

                    HStack(spacing: 10) {
                        Button { showIncome = true } label: { Label("Argent reçu", systemImage: "plus") }.buttonStyle(GlassButtonStyle())
                        Button { showPicker = true } label: { Label("Scanner un ticket", systemImage: "doc.text.viewfinder") }.buttonStyle(GlassButtonStyle())
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Dépense rapide : 1) catégorie  2) montant").font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                            ForEach(Finance.categories, id: \.name) { c in
                                let sel = category == c.name
                                Button { category = c.name; Haptic.tap() } label: {
                                    VStack(spacing: 4) { Image(systemName: c.icon); Text(c.name).font(.caption) }
                                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                                        .foregroundStyle(sel ? Color.black : Color.white)
                                        .background { if sel { RoundedRectangle(cornerRadius: 14).fill(Color.white) } }
                                        .overlay { if !sel { RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.25)) } }
                                }.buttonStyle(PressStyle())
                            }
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 8)], spacing: 8) {
                            ForEach(Finance.amounts, id: \.self) { a in
                                Button { spend(a) } label: {
                                    Text(fmtKg(a)).font(.headline.monospacedDigit()).frame(maxWidth: .infinity).padding(.vertical, 12).glassCard(16)
                                }.buttonStyle(PressStyle())
                            }
                        }
                        HStack {
                            TextField("Autre montant", text: $custom).keyboardType(.decimalPad).padding(12).glassCard(14)
                            Button("Ajouter") {
                                if let a = Double(custom.replacingOccurrences(of: ",", with: ".")) { spend(a); custom = "" }
                            }.buttonStyle(PressStyle()).fontWeight(.bold)
                        }
                    }
                    .padding(16).glassCard(24)

                    if scanning { ProgressView("Nexus lit le ticket…") }
                    if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Historique").font(.headline)
                            Spacer()
                            if store.txns.count > 20 { Button(showAll ? "Moins" : "Tout voir") { showAll.toggle() }.font(.caption) }
                        }
                        if store.txns.isEmpty { Text("Aucune opération.").font(.caption).foregroundStyle(.secondary) }
                        ForEach(store.txns.sorted { $0.date > $1.date }.prefix(showAll ? 500 : 20)) { t in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(t.note.isEmpty ? t.category : t.note)
                                    Text("\(t.category) · \(t.date.formatted(.dateTime.day().month(.abbreviated)))").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Fmt.signedMoney(t.amount, store.currency)).monospacedDigit()
                                Button { store.engine.apply(.delete(.txn(t.id))); Haptic.tap() } label: {
                                    Image(systemName: "trash").font(.caption).foregroundStyle(.secondary).frame(width: 32, height: 32)
                                }
                                .buttonStyle(PressStyle())
                            }
                        }
                        Text("Une suppression se rattrape avec « Annuler » dans le Journal Nexus.").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard(24)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Finances")
        .alert("Argent reçu (\(store.currency))", isPresented: $showIncome) {
            TextField("Montant", text: $incomeText).keyboardType(.decimalPad)
            Button("Ajouter") {
                if let a = Double(incomeText.replacingOccurrences(of: ",", with: ".")) {
                    let r = store.engine.apply(.income(amount: a, note: "Argent de poche"))
                    message = r.summary
                }
                incomeText = ""
            }
            Button("Annuler", role: .cancel) { incomeText = "" }
        }
        .photoPicker(isPresented: $showPicker) { scan($0) }
    }

    private func spend(_ amount: Double) {
        guard amount > 0 else { return }
        guard let category else { Haptic.warn(); message = "Choisis d'abord une catégorie."; return }
        let r = store.engine.apply(.expense(amount: amount, category: category, note: ""))
        message = r.summary
        if r.status == .applied { Haptic.success() } else { Haptic.warn() }
    }

    private func scan(_ image: UIImage) {
        scanning = true; message = ""
        Task {
            do {
                let t = try await gemini.scanReceipt(image: image)
                let r = store.engine.apply(.expense(amount: abs(t.amount), category: t.category, note: t.note))
                message = "Ticket : " + r.summary
                Haptic.success()
            } catch { message = error.localizedDescription }
            scanning = false
        }
    }
}

// MARK: - Notes
struct NotesView: View {
    @EnvironmentObject var store: AppStore
    @State private var draft = ""

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 14) {
                    HStack(alignment: .top) {
                        TextField("Nouvelle note (ou dicte avec le micro)", text: $draft, axis: .vertical).lineLimit(3...8)
                        VStack {
                            DictationButton(text: $draft)
                            Button {
                                let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !t.isEmpty else { return }
                                store.engine.apply(.note(text: t)); draft = ""; Haptic.success()
                            } label: { Image(systemName: "checkmark.circle.fill").font(.title).frame(width: 44, height: 44) }
                        }
                    }
                    .padding(14).glassCard(24)

                    ForEach(store.notes.sorted { $0.date > $1.date }) { n in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(n.text).textSelection(.enabled)
                            Text(n.date, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16).glassCard(20)
                        .contextMenu { Button("Supprimer", role: .destructive) { store.engine.apply(.delete(.note(n.id))) } }
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Notes")
    }
}

// MARK: - Réglages
struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var gemini: GeminiClient
    @AppStorage("geminiKey") private var key = ""
    @AppStorage("geminiModel") private var model = ""
    @AppStorage("autoNoise") private var autoNoise = true
    @ObservedObject private var live = LiveActivityManager.shared
    @State private var info = ""
    @State private var keyStatus = ""
    @State private var testing = false
    @State private var editProfile = false

    var body: some View {
        Form {
            Section("Profil") {
                let p = store.profileOrDefault
                Text("\(store.displayName) · \(p.age) ans · \(Int(p.heightCm)) cm · \(fmtKg(p.weightKg)) kg").font(.subheadline)
                Text("\(p.cityLabel) · \(p.currency) · réveil \(timeString(p.wakeMinute)), coucher \(timeString(p.bedMinute))").font(.caption).foregroundStyle(.secondary)
                Button("Modifier mon profil, mes objectifs et mon rythme") { editProfile = true }
            }
            Section("Clé API Gemini") {
                SecureField("Colle ta clé (aistudio.google.com/apikey)", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                HStack {
                    Button("Coller") { if let s = UIPasteboard.general.string { key = s.trimmingCharacters(in: .whitespacesAndNewlines) } }
                    Spacer()
                    Button(testing ? "Test…" : "Tester la clé") {
                        testing = true
                        Task { let r = await gemini.testKey(key); keyStatus = r.message; testing = false }
                    }
                    .disabled(testing || key.isEmpty)
                }
                .buttonStyle(.borderless)
                if !keyStatus.isEmpty { Text(keyStatus).font(.caption) }
                Link("Créer une clé gratuite sur Google AI Studio", destination: URL(string: "https://aistudio.google.com/apikey")!)
            }
            Section("Modèle IA (vide = \(GeminiClient.defaultModel))") {
                TextField(GeminiClient.defaultModel, text: $model).textInputAutocapitalization(.never).autocorrectionDisabled()
                if !gemini.availableModels.isEmpty {
                    Picker("Choisir dans la liste", selection: $model) {
                        Text("Automatique").tag("")
                        ForEach(gemini.availableModels, id: \.self) { Text($0).tag($0) }
                    }
                }
                if !gemini.activeModel.isEmpty { Text("Dernier modèle utilisé : \(gemini.activeModel)").font(.caption).foregroundStyle(.secondary) }
                Text("Si Google répond 503/429, l'app essaie automatiquement d'autres modèles flash.").font(.caption2).foregroundStyle(.secondary)
            }
            Section("Objectifs quotidiens") {
                Stepper(value: $store.calorieGoal, in: 1500...5000, step: 50) { Text("Calories : \(Int(store.calorieGoal)) kcal") }
                Stepper(value: $store.proteinGoal, in: 40...250, step: 5) { Text("Protéines : \(Int(store.proteinGoal)) g") }
                Text("Les estimations nutritionnelles de l'IA sont approximatives.").font(.caption2).foregroundStyle(.secondary)
            }
            Section("Focus") {
                Toggle("Bruit d'ambiance en Lockdown", isOn: $autoNoise)
            }
            Section("Dynamic Island") {
                Text(live.diagnostic).font(.footnote)
                Button("Tester la Dynamic Island (2 min)") {
                    LiveActivityManager.shared.start(mode: "focus", title: "Test SELF BUILD", subtitle: "Quitte l'app pour la voir", minutes: 2)
                }
                Button("Arrêter") { LiveActivityManager.shared.end() }
                Text("La Live Activity n'est visible que HORS de l'app (écran d'accueil ou verrouillé). iOS interdit les animations continues : Nexus change de pose toutes les ~8 s tant que l'app tourne.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section("Actions") {
                Button("Régénérer le planning du jour") { store.resetToday(); info = "Planning régénéré."; Haptic.success() }
                Button("Reprogrammer les rappels (tâches + IA)") {
                    Task {
                        await NotificationManager.shared.refreshProactive(store: store, gemini: gemini)
                        info = "Rappels reprogrammés."
                    }
                }
                if !info.isEmpty { Text(info).font(.caption).foregroundStyle(.secondary) }
                Text("Notifications « urgentes » : sans l'entitlement payant Time Sensitive, iOS peut les afficher comme des notifications normales.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Réglages")
        .sheet(isPresented: $editProfile) { OnboardingView() }
    }
}
