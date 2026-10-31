import SwiftUI

/// Mascotte en verre liquide noir & blanc : regard qui bouge, clignements, « coucou » à l'arrivée, pulsation quand Nexus réfléchit.
struct MascotView: View {
    var thinking = false
    var size: CGFloat = 120
    @State private var look = CGSize.zero
    @State private var blink = false
    @State private var pulse = false
    @State private var showHand = false
    @State private var swing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(thinking ? 0.40 : 0.08))
                .frame(width: size, height: size)
                .blur(radius: size * 0.25)
                .scaleEffect(pulse ? 1.4 : 0.95)
                .animation(thinking ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .easeOut(duration: 0.4), value: pulse)

            Color.clear
                .frame(width: size, height: size)
                .glassCard(size / 2)
                .overlay {
                    ZStack {
                        Circle().fill(Color.black.opacity(0.45))
                        Capsule().fill(Color.white.opacity(0.35))
                            .frame(width: size * 0.34, height: size * 0.07)
                            .rotationEffect(.degrees(-30))
                            .offset(x: -size * 0.18, y: -size * 0.30).blur(radius: 1)
                        HStack(spacing: size * 0.16) { eye; eye }.offset(look)
                    }
                }
                .scaleEffect(thinking ? 1.04 : 1)
                .animation(.easeInOut(duration: 0.6), value: thinking)

            if showHand {
                Image(systemName: "hand.wave.fill")
                    .font(.system(size: size * 0.28))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(swing ? 22 : -15), anchor: .bottom)
                    .animation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true), value: swing)
                    .offset(x: size * 0.62, y: -size * 0.30)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: size * 1.6, height: size * 1.4)
        .onChange(of: thinking, initial: true) { _, new in pulse = new }
        .task {
            withAnimation(.spring) { showHand = true }
            swing = true
            try? await Task.sleep(for: .seconds(3.2))
            withAnimation(.easeOut) { showHand = false }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 1.5...3.5)))
                withAnimation(.spring(duration: 0.5)) {
                    look = CGSize(width: .random(in: -size * 0.12...size * 0.12), height: .random(in: -size * 0.06...size * 0.06))
                }
                if Int.random(in: 0..<3) == 0 {
                    withAnimation(.easeInOut(duration: 0.1)) { blink = true }
                    try? await Task.sleep(for: .milliseconds(140))
                    withAnimation(.easeInOut(duration: 0.1)) { blink = false }
                }
            }
        }
    }

    private var eye: some View {
        Capsule().fill(Color.white).frame(width: size * 0.09, height: blink ? 2 : size * 0.2)
    }
}
