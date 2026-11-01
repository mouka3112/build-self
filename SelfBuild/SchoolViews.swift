import SwiftUI

private let weekdayNames = ["", "Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"]
private func minutesToDate(_ m: Int) -> Date {
    Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
}
private func dateToMinutes(_ d: Date) -> Int {
    let c = Calendar.current.dateComponents([.hour, .minute], from: d); return (c.hour ?? 0) * 60 + (c.minute ?? 0)
}

// MARK: - Cours particuliers (دروس خصوصية) : séance hebdo, paiement en fin de mois
struct TutorsView: View {
    @EnvironmentObject var store: AppStore
    @State private var showAdd = false

    private func monthSessions(_ t: Tutor) -> [TutorSession] {
        store.tutorSessions.filter { $0.tutorID == t.id && Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 14) {
                    if store.tutors.isEmpty {
                        Text("Ajoute ton prof de cours particuliers : tu auras un rappel avant chaque séance et un rappel de paiement à la fin du mois.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                    }
                    ForEach(store.tutors) { t in
                        let done = monthSessions(t)
                        let unpaid = done.filter { !$0.paid }
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(t.name).font(.headline)
                                    Text("\(t.subject) · \(weekdayNames[t.weekday]) \(timeString(t.hour * 60 + t.minute))").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(done.count)/\(t.sessionsPerMonth)").font(.title3.bold().monospacedDigit())
                            }
                            GaugeBar(title: "Séances ce mois", value: Double(done.count), goal: Double(t.sessionsPerMonth), unit: "")
                            Button {
                                store.tutorSessions.append(TutorSession(tutorID: t.id, date: .now)); Haptic.success()
                            } label: { Label("Séance faite ✅", systemImage: "checkmark") }.buttonStyle(GlassButtonStyle())
                            Button { pay(t, unpaid) } label: {
                                Label(unpaid.isEmpty ? "Rien à payer" : String(format: "Khallast 💸 – payer %.2f TND", Double(unpaid.count) * t.price), systemImage: "banknote")
                            }.buttonStyle(GlassButtonStyle(prominent: !unpaid.isEmpty)).disabled(unpaid.isEmpty)
                            Text("Paiement : en fin de mois (rappel automatique à 18 h le dernier jour).").font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(16).glassCard(24)
                        .contextMenu {
                            Button("Supprimer", role: .destructive) {
                                NotificationManager.shared.cancelTutor(t)
                                store.tutors.removeAll { $0.id == t.id }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Cours particuliers")
        .toolbar { Button { showAdd = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showAdd) { AddTutorSheet() }
    }

    private func pay(_ t: Tutor, _ unpaid: [TutorSession]) {
        guard !unpaid.isEmpty else { return }
        let amount = Double(unpaid.count) * t.price
        store.txns.append(Txn(date: .now, amount: -amount, category: "Études", note: "Cours \(t.subject) – \(t.name)"))
        for i in store.tutorSessions.indices where unpaid.contains(where: { $0.id == store.tutorSessions[i].id }) { store.tutorSessions[i].paid = true }
        Haptic.success()
    }
}

struct AddTutorSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var subject = "Maths"
    @State private var price = "30"
    @State private var weekday = 2
    @State private var time = minutesToDate(17 * 60)

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom du prof", text: $name)
                Picker("Matière", selection: $subject) { ForEach(schoolSubjects, id: \.self) { Text($0) } }
                TextField("Prix par séance (TND)", text: $price).keyboardType(.decimalPad)
                Picker("Jour de la séance", selection: $weekday) { ForEach(1...7, id: \.self) { Text(weekdayNames[$0]).tag($0) } }
                DatePicker("Heure", selection: $time, displayedComponents: .hourAndMinute)
                Text("4 séances par mois (une par semaine), paiement en fin de mois.").font(.caption).foregroundStyle(.secondary)
            }
            .scrollContentBackground(.hidden).background(AppBackground())
            .navigationTitle("Nouveau prof")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        let m = dateToMinutes(time)
                        let t = Tutor(name: name.isEmpty ? "Prof" : name, subject: subject,
                                      price: Double(price.replacingOccurrences(of: ",", with: ".")) ?? 0,
                                      weekday: weekday, hour: m / 60, minute: m % 60)
                        store.tutors.append(t)
                        NotificationManager.shared.scheduleTutor(t)
                        dismiss()
                    }
                }
            }
        }
        .hideKeyboardOnTap()
    }
}

// MARK: - Emploi du temps scolaire (fixe) + contrôles
struct SchoolView: View {
    @EnvironmentObject var store: AppStore
    @State private var showEntry = false
    @State private var showExam = false

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("Contrôles").font(.headline); Spacer(); Button { showExam = true } label: { Image(systemName: "plus.circle.fill").font(.title3) } }
                        if store.upcomingExams.isEmpty { Text("Aucun contrôle prévu.").font(.caption).foregroundStyle(.secondary) }
                        ForEach(store.upcomingExams) { e in
                            let d = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: e.date)).day ?? 0
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(e.subject).font(.headline)
                                    if !e.topic.isEmpty { Text(e.topic).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Text(d == 0 ? "Aujourd'hui" : d == 1 ? "Demain" : "J-\(d)").font(.subheadline.bold())
                            }
                            .contextMenu { Button("Supprimer", role: .destructive) { store.exams.removeAll { $0.id == e.id } } }
                        }
                        Text("Nexus les prend en compte : il ajoute des révisions dans ton planning les 3 jours avant.").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard(24)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("Emploi du temps").font(.headline); Spacer(); Button { showEntry = true } label: { Image(systemName: "plus.circle.fill").font(.title3) } }
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { wd in
                            let list = store.timetable.filter { $0.weekday == wd }.sorted { $0.start < $1.start }
                            if !list.isEmpty {
                                Text(weekdayNames[wd]).font(.subheadline.bold()).padding(.top, 4)
                                ForEach(list) { c in
                                    HStack {
                                        Text("\(timeString(c.start)) – \(timeString(c.end))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                        Text(c.subject)
                                        Spacer()
                                    }
                                    .contextMenu { Button("Supprimer", role: .destructive) { store.timetable.removeAll { $0.id == c.id } } }
                                }
                            }
                        }
                        if store.timetable.isEmpty { Text("Ajoute tes cours : ils remplaceront le bloc « Cours » de ton planning.").font(.caption).foregroundStyle(.secondary) }
                        Button("Régénérer mon planning du jour") { store.resetToday(); Haptic.success() }.buttonStyle(GlassButtonStyle())
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard(24)
                }
                .padding()
            }
        }
        .navigationTitle("Emploi du temps")
        .sheet(isPresented: $showEntry) { AddTimetableSheet() }
        .sheet(isPresented: $showExam) { AddExamSheet() }
    }
}

struct AddTimetableSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var weekday = 2
    @State private var subject = "Maths"
    @State private var start = minutesToDate(8 * 60)
    @State private var end = minutesToDate(9 * 60)

    var body: some View {
        NavigationStack {
            Form {
                Picker("Jour", selection: $weekday) { ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { Text(weekdayNames[$0]).tag($0) } }
                Picker("Matière", selection: $subject) { ForEach(schoolSubjects, id: \.self) { Text($0) } }
                DatePicker("Début", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("Fin", selection: $end, displayedComponents: .hourAndMinute)
            }
            .scrollContentBackground(.hidden).background(AppBackground())
            .navigationTitle("Nouveau cours")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        store.timetable.append(TimetableEntry(weekday: weekday, start: dateToMinutes(start), end: max(dateToMinutes(end), dateToMinutes(start) + 15), subject: subject))
                        Haptic.success()
                    }
                }
            }
        }
    }
}

struct AddExamSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var subject = "Maths"
    @State private var date = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var topic = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Matière", selection: $subject) { ForEach(schoolSubjects, id: \.self) { Text($0) } }
                DatePicker("Date du contrôle", selection: $date, in: Date()..., displayedComponents: .date)
                TextField("Chapitres / thème", text: $topic)
            }
            .scrollContentBackground(.hidden).background(AppBackground())
            .navigationTitle("Nouveau contrôle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") { store.exams.append(ExamItem(subject: subject, date: date, topic: topic)); Haptic.success(); dismiss() }
                }
            }
        }
        .hideKeyboardOnTap()
    }
}

// MARK: - Mes cours en photos (stockage local + partage vers Google Drive + questions à Nexus)
struct LessonsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var gemini: GeminiClient
    @State private var subject = "Maths"
    @State private var showPicker = false
    @State private var busy = false
    @State private var question = ""
    @State private var answer = ""
    @State private var selected: LessonPhoto?

    private var grouped: [(Date, [LessonPhoto])] {
        let g = Dictionary(grouping: store.lessons) { Calendar.current.startOfDay(for: $0.date) }
        return g.keys.sorted(by: >).map { ($0, g[$0] ?? []) }
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 10) {
                        Picker("Matière", selection: $subject) { ForEach(schoolSubjects, id: \.self) { Text($0) } }.pickerStyle(.menu)
                        Button { showPicker = true } label: { Label("Photographier un cours", systemImage: "camera.fill") }
                            .buttonStyle(GlassButtonStyle(prominent: true)).disabled(busy)
                        if busy { ProgressView("Nexus résume le cours…") }
                        Text("Les photos restent sur ton iPhone. Pour les mettre dans Google Drive : ouvre une photo → Partager → Drive.").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(16).glassCard(24)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Demander à Nexus sur mes cours").font(.headline)
                        HStack(alignment: .top) {
                            TextField("Ex : explique-moi le chapitre de SVT", text: $question, axis: .vertical).lineLimit(1...4)
                            DictationButton(text: $question)
                        }.padding(12).glassCard(14)
                        Button { ask() } label: { Label("Demander", systemImage: "sparkles") }.buttonStyle(GlassButtonStyle()).disabled(question.isEmpty || busy)
                        if !answer.isEmpty { Text(answer).font(.callout) }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard(24)

                    ForEach(grouped, id: \.0) { day, list in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(day, format: .dateTime.weekday(.wide).day().month(.wide)).font(.headline)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                                ForEach(list) { l in
                                    Button { selected = l } label: {
                                        ZStack(alignment: .bottomLeading) {
                                            if let img = PhotoStore.load(l.file) {
                                                Image(uiImage: img).resizable().scaledToFill().frame(height: 110).clipped()
                                            }
                                            Text(l.subject).font(.caption2.bold()).padding(4).background(.black.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: 6)).padding(4)
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }.buttonStyle(.plain)
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
        .navigationTitle("Mes cours")
        .photoPicker(isPresented: $showPicker) { add($0) }
        .sheet(item: $selected) { LessonDetail(lesson: $0) }
    }

    private func add(_ img: UIImage) {
        guard let file = PhotoStore.save(img) else { return }
        let lesson = LessonPhoto(date: .now, subject: subject, file: file, summary: nil)
        store.lessons.append(lesson)
        busy = true
        Task {
            let s = try? await gemini.text("Résume ce cours de \(lesson.subject) en 4 lignes maximum (notions clés, formules, définitions). Français.", image: img)
            if let i = store.lessons.firstIndex(where: { $0.id == lesson.id }) { store.lessons[i].summary = s }
            busy = false
        }
    }

    private func ask() {
        busy = true; answer = ""
        let images = store.lessons.sorted { $0.date > $1.date }.prefix(3).compactMap { PhotoStore.load($0.file) }
        Task {
            do { answer = try await gemini.text("Question de Melik sur ses cours : \(question)\nRéponds en t'appuyant sur ses résumés de cours (contexte) et sur les photos jointes. Sois pédagogue et clair.", images: images, store: store) }
            catch { answer = error.localizedDescription }
            busy = false
        }
    }
}

struct LessonDetail: View {
    let lesson: LessonPhoto
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var gemini: GeminiClient
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""
    @State private var answer = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        if let img = PhotoStore.load(lesson.file) {
                            Image(uiImage: img).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 16))
                            ShareLink(item: URL(fileURLWithPath: PhotoStore.dir.appendingPathComponent(lesson.file).path)) {
                                Label("Partager / envoyer vers Google Drive", systemImage: "square.and.arrow.up")
                            }.buttonStyle(GlassButtonStyle())
                        }
                        if let s = lesson.summary { Text(s).font(.callout).padding(14).glassCard(18) }
                        HStack(alignment: .top) {
                            TextField("Pose une question sur ce cours…", text: $q, axis: .vertical).lineLimit(1...3)
                            DictationButton(text: $q)
                        }.padding(12).glassCard(14)
                        Button { ask() } label: { Label(busy ? "Nexus réfléchit…" : "Demander à Nexus", systemImage: "sparkles") }
                            .buttonStyle(GlassButtonStyle(prominent: true)).disabled(q.isEmpty || busy)
                        if !answer.isEmpty { Text(answer).font(.callout).padding(14).glassCard(18) }
                        Button("Supprimer cette photo", role: .destructive) {
                            store.lessons.removeAll { $0.id == lesson.id }; dismiss()
                        }.font(.footnote)
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(lesson.subject)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
        .hideKeyboardOnTap()
    }

    private func ask() {
        busy = true
        Task {
            let img = PhotoStore.load(lesson.file)
            do { answer = try await gemini.text("Cours de \(lesson.subject). Question de Melik : \(q). Réponds clairement en te basant sur la photo du cours.", image: img, store: store) }
            catch { answer = error.localizedDescription }
            busy = false
        }
    }
}

// MARK: - Rappels (avec répétition)
struct RemindersView: View {
    @EnvironmentObject var store: AppStore
    @State private var title = ""
    @State private var date = Date().addingTimeInterval(3600)
    @State private var rule = "none"
    @State private var urgent = true

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 10) {
                        HStack(alignment: .top) {
                            TextField("De quoi dois-je te rappeler ?", text: $title, axis: .vertical).lineLimit(1...3)
                            DictationButton(text: $title)
                        }.padding(12).glassCard(14)
                        DatePicker("Quand", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        Picker("Répétition", selection: $rule) {
                            Text("Une fois").tag("none"); Text("Chaque jour").tag("daily"); Text("Chaque semaine").tag("weekly"); Text("Chaque mois").tag("monthly")
                        }.pickerStyle(.menu)
                        Toggle("Urgent (passe devant le mode Concentration)", isOn: $urgent).font(.subheadline)
                        Button { add() } label: { Label("Programmer", systemImage: "bell.badge.fill") }
                            .buttonStyle(GlassButtonStyle(prominent: true)).disabled(title.isEmpty)
                        Text("Tu peux aussi dire à Nexus : « rappelle-moi tous les lundis à 18 h de ranger mes affaires ».").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(16).glassCard(24)

                    ForEach(store.reminders.sorted { $0.date < $1.date }) { r in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(r.title).font(.headline)
                                Text("\(r.date.formatted(date: .abbreviated, time: .shortened)) · \(label(r.repeatRule))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { delete(r) } label: { Image(systemName: "trash").foregroundStyle(.secondary) }
                        }
                        .padding(16).glassCard(20)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Rappels")
    }

    private func label(_ r: String) -> String { r == "daily" ? "chaque jour" : r == "weekly" ? "chaque semaine" : r == "monthly" ? "chaque mois" : "une fois" }

    private func add() {
        let r = UserReminder(title: title, date: date, repeatRule: rule, urgent: urgent)
        store.reminders.append(r)
        NotificationManager.shared.scheduleReminder(r)
        title = ""; Haptic.success()
    }
    private func delete(_ r: UserReminder) {
        NotificationManager.shared.cancelReminder(r.id)
        store.reminders.removeAll { $0.id == r.id }
    }
}
