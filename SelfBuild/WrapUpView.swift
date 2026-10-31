import SwiftUI

struct ConfettiView: View {
    struct Piece { let x: CGFloat; let r: Double; let w: CGFloat; let delay: Double; let strong: Bool }
    @State private var go = false
    @State private var pieces: [Piece] = (0..<44).map { _ in
        Piece(x: .random(in: -170...170), r: .random(in: 0...360), w: .random(in: 6...13), delay: .random(in: 0...0.5), strong: Bool.random())
    }
    var body: some View {
        ZStack {
            ForEach(0..<pieces.count, id: \.self) { i in
                let p = pieces[i]
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(p.strong ? 1 : 0.5))
                    .frame(width: p.w, height: p.w * 1.7)
                    .rotationEffect(.degrees(go ? p.r + 540 : p.r))
                    .offset(x: go ? p.x : 0, y: go ? 520 : -80)
                    .opacity(go ? 0.0 : 1)
                    .animation(.easeIn(duration: 2.4).delay(p.delay), value: go)
            }
        }
        .onAppear { go = true }
        .allowsHitTesting(false)
    }
}

/// Animation de fin de séance / session + bilan « mieux / moins bien » + photo de progression (privée).
struct WrapUpView: View {
    let kind: String
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var phase = 0
    @State private var states: [String: Int] = [:]   // 0 neutre, 1 mieux, 2 moins bien
    @State private var note = ""
    @State private var photo: UIImage?
    @State private var showPicker = false
    @State private var appear = false

    private var isWorkout: Bool { kind == "workout" }
    private var aspects: [String] {
        isWorkout ? ["Force", "Endurance", "Technique", "Énergie", "Motivation", "Récupération"]
                  : ["Concentration", "Compréhension", "Mémoire", "Organisation", "Motivation", "Fatigue"]
    }

    var body: some View {
        ZStack {
            AppBackground()
            if phase == 0 { celebration } else { form }
        }
        .hideKeyboardOnTap()
        .interactiveDismissDisabled(phase == 0)
        .photoPicker(isPresented: $showPicker) { photo = $0 }
        .task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeInOut) { phase = 1 }
        }
    }

    private var celebration: some View {
        ZStack {
            ConfettiView()
            VStack(spacing: 18) {
                MascotView(thinking: true, size: 120).scaleEffect(appear ? 1 : 0.3)
                Text(isWorkout ? "Séance terminée 💪" : "Session validée 🧠")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold)).multilineTextAlignment(.center)
                Text(["La discipline bat la motivation.", "Un jour de plus, une version plus forte.", "Personne ne le fera à ta place. Tu l'as fait."].randomElement() ?? "")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            }
            .opacity(appear ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(duration: 0.8, bounce: 0.4)) { appear = true }; Haptic.success() }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ton bilan").font(.system(.title, design: .rounded).weight(.bold))
                Text("Touche une case : ↑ = amélioré, ↓ = moins bien, une 3ᵉ fois = neutre.").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(aspects, id: \.self) { a in
                        let s = states[a] ?? 0
                        Button { states[a] = (s + 1) % 3; Haptic.tap() } label: {
                            HStack {
                                Text(a)
                                Spacer()
                                Text(s == 1 ? "↑" : s == 2 ? "↓" : "·").font(.headline)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .foregroundStyle(s == 1 ? Color.black : Color.white)
                            .background { if s == 1 { RoundedRectangle(cornerRadius: 16).fill(Color.white) } }
                            .overlay { if s != 1 { RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(s == 2 ? 0.7 : 0.25), style: StrokeStyle(lineWidth: 1, dash: s == 2 ? [4] : [])) } }
                        }.buttonStyle(PressStyle())
                    }
                }
                HStack(alignment: .top) {
                    TextField("Une remarque ? (ou dicte)", text: $note, axis: .vertical).lineLimit(2...5)
                    DictationButton(text: $note)
                }
                .padding(12).glassCard(20)

                if isWorkout {
                    VStack(alignment: .leading, spacing: 8) {
                        Button { showPicker = true } label: { Label(photo == nil ? "Photo de progression (optionnelle)" : "Photo ajoutée ✓", systemImage: "camera.fill") }
                            .buttonStyle(GlassButtonStyle())
                        Text("Elle reste uniquement sur ton iPhone (jamais envoyée à l'IA) et se consulte derrière Face ID.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button { save() } label: { Text("Enregistrer") }.buttonStyle(GlassButtonStyle(prominent: true))
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func save() {
        let file = photo.flatMap { PhotoStore.save($0) }
        store.reviews.append(SessionReview(date: .now, kind: kind,
                                           improved: aspects.filter { states[$0] == 1 },
                                           worsened: aspects.filter { states[$0] == 2 },
                                           note: note, photo: file))
        Haptic.success(); dismiss()
    }
}
