import SwiftUI

struct PlusView: View {
    private let items: [AppDestination] = [.study, .hygiene, .finance, .wardrobe, .kitchen, .running, .music, .projects, .challenges, .capsule, .reports, .health, .safe, .notes, .settings]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(items) { d in
                            NavigationLink { DestinationView(dest: d).hideKeyboardOnTap() } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: d.icon).font(.title2).frame(width: 36)
                                    Text(d.title).font(.headline)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }
                                .padding(18).glassCard(24)
                            }
                            .buttonStyle(PressStyle())
                        }
                    }.padding()
                }
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
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Mode Lockdown", systemImage: "lock.fill").font(.headline)
                        Text("Écran verrouillé et concentré. Pour sortir : prouve tes devoirs avec une photo analysée par Nexus.")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("Durée", selection: $lockMinutes) {
                            ForEach([30, 45, 60, 90, 120], id: \.self) { Text("\($0) min").tag($0) }
                        }.pickerStyle(.segmented)
                        Button {
                            store.lockdownEnd = Date().addingTimeInterval(Double(lockMinutes) * 60)
                            store.lockdownActive = true
                            LiveActivityManager.shared.start(mode: "focus", title: "Lockdown", subtitle: "Devoirs d'abord", minutes: lockMinutes)
                            if UserDefaults.standard.object(forKey: "autoNoise") as? Bool ?? true { MusicManager.shared.startNoise() }
                        } label: { Text("Activer le Lockdown") }
                            .buttonStyle(GlassButtonStyle(prominent: true))
                    }
                    .padding(16).glassCard(24)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Devoirs").font(.headline)
                        if store.homework.isEmpty { Text("Aucun devoir. Appuie sur + pour en ajouter.").foregroundStyle(.secondary) }
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
                            .contextMenu { Button("Supprimer", role: .destructive) { store.homework.removeAll { $0.id == hw.id } } }
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard(24)
                }
                .padding()
            }
        }
        .navigationTitle("Études")
        .toolbar { Button { showAdd = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showAdd) { AddHomeworkSheet() }
    }

    private func toggle(_ hw: Homework) {
        if let i = store.homework.firstIndex(where: { $0.id == hw.id }) { store.homework[i].done.toggle() }
    }
}

struct AddHomeworkSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var subject = "Maths"
    @State private var title = ""
    @State private var due = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now

    var body: some View {
        NavigationStack {
            Form {
                Picker("Matière", selection: $subject) { ForEach(schoolSubjects, id: \.self) { Text($0) } }
                TextField("Intitulé (ex : exercices p.45)", text: $title)
                DatePicker("Rendu le", selection: $due, displayedComponents: .date)
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Nouveau devoir")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        store.homework.append(Homework(subject: subject, title: title.isEmpty ? "Devoir" : title, due: due))
                        dismiss()
                    }
                }
            }
        }
        .hideKeyboardOnTap()
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

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill").font(.system(size: 44))
                    .onLongPressGesture(minimumDuration: 5) { unlock() }     // sortie de secours (bug réseau/IA) : maintiens 5 s
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let rem = max(0, Int((store.lockdownEnd ?? ctx.date).timeIntervalSince(ctx.date)))
                    Text(String(format: "%02d:%02d", rem / 60, rem % 60))
                        .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                }
                Text("Concentre-toi. Les devoirs d'abord.").foregroundStyle(.secondary)

                if !store.pendingHomework.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.pendingHomework) { hw in
                            HStack { Image(systemName: "circle"); Text("\(hw.subject) – \(hw.title)"); Spacer() }
                        }
                    }
                    .padding(16).glassCard(22)
                }

                if store.pendingHomework.isEmpty {
                    Button { unlock() } label: { Text("Terminer le Lockdown") }.buttonStyle(GlassButtonStyle(prominent: true))
                } else {
                    Button { showPicker = true } label: { Label("Valider mes devoirs en photo", systemImage: "camera.fill") }
                        .buttonStyle(GlassButtonStyle(prominent: true))
                        .disabled(checking)
                }
                if checking { ProgressView("Nexus vérifie…") }
                if !feedback.isEmpty { Text(feedback).multilineTextAlignment(.center).padding(.horizontal) }
                Spacer()
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
                let r = try await gemini.validateHomework(image: image, pending: pending)
                feedback = r.comment
                if r.valid {
                    for idx in r.validatedIndices where idx >= 1 && idx <= pending.count {
                        if let i = store.homework.firstIndex(where: { $0.id == pending[idx - 1].id }) { store.homework[i].done = true }
                    }
                    if store.pendingHomework.isEmpty { Haptic.success(); unlock() }
                } else { Haptic.warn() }
            } catch { feedback = error.localizedDescription }
            checking = false
        }
    }

    private func unlock() {
        store.lockdownActive = false
        store.lockdownEnd = nil
        LiveActivityManager.shared.end()
        MusicManager.shared.stopNoise()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { router.wrapUp = WrapUpRequest(kind: "study") }
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

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text("Solde disponible").font(.caption).foregroundStyle(.secondary)
                        Text(String(format: "%.2f TND", store.balance)).font(.system(size: 40, weight: .bold, design: .rounded))
                        Text(String(format: "Dépensé ce mois : %.2f TND", store.monthSpent)).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(20).glassCard(28)

                    HStack(spacing: 10) {
                        Button { showIncome = true } label: { Label("Argent reçu", systemImage: "plus") }.buttonStyle(GlassButtonStyle())
                        Button { showPicker = true } label: { Label("Scanner", systemImage: "doc.text.viewfinder") }.buttonStyle(GlassButtonStyle())
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
                        Text("Historique").font(.headline)
                        ForEach(store.txns.sorted { $0.date > $1.date }.prefix(20)) { t in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(t.note.isEmpty ? t.category : t.note)
                                    Text("\(t.category) · \(t.date.formatted(.dateTime.day().month(.abbreviated)))").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(String(format: "%+.2f", t.amount)).monospacedDigit()
                            }
                            .contextMenu { Button("Supprimer", role: .destructive) { store.txns.removeAll { $0.id == t.id } } }
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard(24)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Finances")
        .alert("Argent reçu (TND)", isPresented: $showIncome) {
            TextField("Montant", text: $incomeText).keyboardType(.decimalPad)
            Button("Ajouter") {
                if let a = Double(incomeText.replacingOccurrences(of: ",", with: ".")), a > 0 {
                    store.txns.append(Txn(date: .now, amount: a, category: "Revenu", note: "Argent de poche"))
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
        store.txns.append(Txn(date: .now, amount: -amount, category: category, note: ""))
        message = String(format: "−%.2f TND · %@", amount, category)
        Haptic.success()
    }

    private func scan(_ image: UIImage) {
        scanning = true; message = ""
        Task {
            do {
                let r = try await gemini.scanReceipt(image: image)
                store.txns.append(Txn(date: .now, amount: -abs(r.amount), category: r.category, note: r.note))
                message = String(format: "Ticket ajouté : −%.3f TND · %@ (%@)", abs(r.amount), r.category, r.note)
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
                                store.notes.insert(NoteItem(date: .now, text: t), at: 0); draft = ""
                            } label: { Image(systemName: "checkmark.circle.fill").font(.title).frame(width: 44, height: 44) }
                        }
                    }
                    .padding(14).glassCard(24)

                    ForEach(store.notes) { n in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(n.text)
                            Text(n.date, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16).glassCard(20)
                        .contextMenu { Button("Supprimer", role: .destructive) { store.notes.removeAll { $0.id == n.id } } }
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
    @State private var info = ""

    var body: some View {
        Form {
            Section("Clé API Gemini") {
                SecureField("Colle ta clé (aistudio.google.com/apikey)", text: $key)
            }
            Section("Modèle IA (laisse vide = automatique)") {
                TextField(GeminiClient.defaultModel, text: $model).textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("Bruit d'ambiance en Lockdown", isOn: $autoNoise)
            }
            Section("Objectifs quotidiens") {
                Stepper(value: $store.calorieGoal, in: 1500...5000, step: 100) { Text("Calories : \(Int(store.calorieGoal)) kcal") }
                Stepper(value: $store.proteinGoal, in: 50...250, step: 5) { Text("Protéines : \(Int(store.proteinGoal)) g") }
            }
            Section("Actions") {
                Button("Régénérer le planning du jour") { store.resetToday() }
                Button("Reprogrammer les rappels IA") {
                    Task {
                        await NotificationManager.shared.refreshProactive(store: store, gemini: gemini)
                        info = "Rappels reprogrammés."
                    }
                }
                if !info.isEmpty { Text(info).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Réglages")
    }
}
