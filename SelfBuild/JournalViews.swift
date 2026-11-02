import SwiftUI

// MARK: - Une action du journal (✅ / ⚠️ / 💡 …) avec Annuler / Appliquer
struct JournalItemRow: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var router: Router
    let entryID: UUID
    let item: JournalItem
    var compact = false

    private var symbol: (String, Color) {
        switch item.status {
        case .applied: return ("checkmark.circle.fill", Color(red: 0.42, green: 0.86, blue: 0.5))
        case .proposed: return ("lightbulb.fill", Color(red: 1.0, green: 0.8, blue: 0.35))
        case .rejected: return ("exclamationmark.triangle.fill", Color(red: 1.0, green: 0.55, blue: 0.4))
        case .duplicate: return ("equal.circle.fill", .secondary)
        case .dismissed: return ("xmark.circle", .secondary)
        case .undone: return ("arrow.uturn.backward.circle", .secondary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if let d = item.destination, item.status != .rejected { router.go(d) }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: symbol.0).foregroundStyle(symbol.1)
                    Text(item.summary)
                        .font(compact ? .caption : .footnote)
                        .foregroundStyle(item.status == .undone || item.status == .dismissed ? Color.secondary : Color.primary)
                        .strikethrough(item.status == .undone)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if item.destination != nil && item.status != .rejected {
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(PressStyle())

            if item.canUndo {
                Button {
                    if store.engine.undo(entryID: entryID, itemID: item.id) { Haptic.tap() }
                } label: { Label("Annuler", systemImage: "arrow.uturn.backward").font(.caption.weight(.semibold)) }
                    .buttonStyle(.bordered).tint(.white).controlSize(.small)
            } else if item.status == .proposed, let a = item.action {
                HStack(spacing: 8) {
                    Button {
                        if store.engine.applyProposal(entryID: entryID, itemID: item.id)?.status == .applied { Haptic.success() } else { Haptic.warn() }
                    } label: { Text(a.proposalLabel).font(.caption.weight(.bold)) }
                        .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black).controlSize(.small)
                    Button("Ignorer") { store.engine.dismissProposal(entryID: entryID, itemID: item.id) }
                        .buttonStyle(.bordered).tint(.white).controlSize(.small)
                }
            }
        }
    }
}

// MARK: - Un échange complet (ce que tu as dit · ce que Nexus a dit · ce qui a été fait)
struct JournalEntryRow: View {
    let entry: JournalEntry
    var showTexts = true

    private var sourceLabel: (String, String) {
        switch entry.source {
        case .nexus: return ("sparkles", "Nexus")
        case .ui: return ("hand.tap.fill", "Toi")
        case .notification: return ("bell.fill", "Notification")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: sourceLabel.0).font(.caption2)
                Text(sourceLabel.1).font(.caption2.weight(.semibold))
                Spacer()
                Text(entry.date, format: .dateTime.hour().minute()).font(.caption2).monospacedDigit()
            }
            .foregroundStyle(.secondary)
            if showTexts, let u = entry.userText, !u.isEmpty {
                Text("Toi : « \(u) »").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if showTexts, let a = entry.aiText, !a.isEmpty {
                Text(a).font(.footnote).lineLimit(3)
                    .foregroundStyle(entry.isError ? Color(red: 1.0, green: 0.55, blue: 0.4) : .primary)
            }
            ForEach(entry.items) { it in
                JournalItemRow(entryID: entry.id, item: it, compact: entry.source != .nexus)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(20)
    }
}

// MARK: - Bandeau « Nexus a dit » (haut du Hub)
struct NexusSaidBanner: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var router: Router
    @State private var expanded = false

    var body: some View {
        if let e = store.lastNexusEntry, let text = e.aiText {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").foregroundStyle(AppDestination.nexus.color)
                    Text("NEXUS A DIT").font(.caption2.weight(.bold)).tracking(2).foregroundStyle(.secondary)
                    Spacer()
                    Text(e.date, format: .dateTime.hour().minute()).font(.caption2).foregroundStyle(.secondary)
                }
                Text(text)
                    .font(.subheadline)
                    .lineLimit(expanded ? nil : 3)
                    .foregroundStyle(e.isError ? Color(red: 1.0, green: 0.55, blue: 0.4) : .primary)
                    .onTapGesture { router.go(.nexus) }
                if text.count > 140 {
                    Button(expanded ? "voir moins" : "voir plus") { withAnimation { expanded.toggle() } }
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(e.items.filter { $0.status == .proposed || $0.status == .rejected }) { it in
                    JournalItemRow(entryID: e.id, item: it)
                }
                let done = e.items.filter { $0.status == .applied }.count
                if done > 0 {
                    Label("\(done) action(s) appliquée(s) — détail dans le Journal", systemImage: "checkmark.seal.fill")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(24)
        }
    }
}

// MARK: - Aperçu du journal dans le Hub
struct JournalPreview: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var router: Router

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("JOURNAL NEXUS").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                Spacer()
                if !store.journal.isEmpty {
                    Button("Tout voir") { router.go(.journal) }.font(.caption.weight(.semibold))
                }
            }
            if store.journal.isEmpty {
                Text("Parle à Nexus ou coche une tâche : chaque action apparaîtra ici, avec « Annuler ».")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).glassCard(20)
            } else {
                ForEach(Array(store.journal.suffix(5).reversed())) { e in JournalEntryRow(entry: e) }
            }
        }
    }
}

// MARK: - Journal complet
struct JournalView: View {
    @EnvironmentObject var store: AppStore
    @State private var onlyNexus = false

    private struct DayGroup: Identifiable { let id: Date; let entries: [JournalEntry] }

    private var days: [DayGroup] {
        let list = store.journal.filter { !onlyNexus || $0.source == .nexus }
        let g = Dictionary(grouping: list) { Calendar.current.startOfDay(for: $0.date) }
        return g.keys.sorted(by: >).map { day in DayGroup(id: day, entries: (g[day] ?? []).sorted { $0.date > $1.date }) }
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Filtre", selection: $onlyNexus) {
                        Text("Tout").tag(false)
                        Text("Nexus").tag(true)
                    }.pickerStyle(.segmented)
                    if store.journal.isEmpty {
                        Text("Aucune action pour l'instant.").foregroundStyle(.secondary)
                    }
                    ForEach(days) { day in
                        Text(day.id, format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.headline).padding(.top, 6)
                        ForEach(day.entries) { e in JournalEntryRow(entry: e) }
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Journal Nexus")
    }
}
