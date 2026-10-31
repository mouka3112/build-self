import SwiftUI

struct HygieneView: View {
    @EnvironmentObject var store: AppStore

    private var doneCount: Int { HygieneHabit.allCases.filter { store.hygieneDone($0) }.count }

    /// Jours consécutifs avec les deux brossages de dents.
    private var streak: Int {
        var n = 0
        var d = Date()
        if !(store.hygieneDone(.teethAM, on: d) && store.hygieneDone(.teethPM, on: d)) {
            d = Calendar.current.date(byAdding: .day, value: -1, to: d) ?? d     // aujourd'hui pas fini : on compte depuis hier
        }
        while store.hygieneDone(.teethAM, on: d) && store.hygieneDone(.teethPM, on: d) {
            n += 1; d = Calendar.current.date(byAdding: .day, value: -1, to: d) ?? d
            if n > 365 { break }
        }
        return n
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 6) {
                        Text("\(doneCount)/\(HygieneHabit.allCases.count)").font(.system(size: 44, weight: .bold, design: .rounded))
                        Text("habitudes faites aujourd'hui").foregroundStyle(.secondary)
                        Label("\(streak) jour(s) de brossage complet d'affilée", systemImage: "flame.fill").font(.footnote)
                    }
                    .frame(maxWidth: .infinity).padding(20).glassCard(28)

                    ForEach(HygieneHabit.allCases) { h in
                        let on = store.hygieneDone(h)
                        Button { store.setHygiene(h, !on); Haptic.tap() } label: {
                            HStack(spacing: 14) {
                                Image(systemName: h.icon).font(.title2).frame(width: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(h.title).font(.headline).strikethrough(on)
                                    Text(h.tip).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title2)
                            }
                            .opacity(on ? 0.55 : 1)
                            .padding(16).glassCard(22)
                        }.buttonStyle(PressStyle())
                    }
                    Text("Nexus te rappelle ces habitudes dans ton planning et par notification.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .navigationTitle("Hygiène")
    }
}
