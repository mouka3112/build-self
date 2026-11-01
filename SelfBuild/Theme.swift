import SwiftUI
import UIKit

// MARK: - Liquid Glass (iOS 26 natif, fallback matériau sur iOS 17+)
struct GlassBackground: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }
    private func fallback(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.05)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(_ radius: CGFloat = 24) -> some View { modifier(GlassBackground(radius: radius)) }

    /// Un tap en dehors d'un champ de texte ferme le clavier.
    func hideKeyboardOnTap() -> some View {
        simultaneousGesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        })
    }
}

extension AppDestination {
    /// Petite touche de couleur par module (discrète).
    var color: Color {
        switch self {
        case .muscu: return Color(red: 1.0, green: 0.62, blue: 0.26)
        case .nutrition, .kitchen: return Color(red: 0.42, green: 0.86, blue: 0.5)
        case .study, .school, .lessons, .tutors: return Color(red: 0.45, green: 0.62, blue: 1.0)
        case .hygiene: return Color(red: 0.4, green: 0.85, blue: 0.95)
        case .finance: return Color(red: 0.4, green: 0.9, blue: 0.7)
        case .health: return Color(red: 1.0, green: 0.45, blue: 0.55)
        case .running: return Color(red: 1.0, green: 0.85, blue: 0.3)
        case .music: return Color(red: 0.75, green: 0.5, blue: 1.0)
        case .reports, .challenges: return Color(red: 1.0, green: 0.8, blue: 0.35)
        case .reminders: return Color(red: 1.0, green: 0.55, blue: 0.4)
        case .safe: return Color(red: 0.6, green: 0.6, blue: 1.0)
        default: return .white
        }
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [Color(red: 0.4, green: 0.45, blue: 1.0).opacity(0.22), .clear], center: .topTrailing, startRadius: 0, endRadius: 460)
            RadialGradient(colors: [Color(red: 0.2, green: 0.8, blue: 0.7).opacity(0.12), .clear], center: .bottomLeading, startRadius: 0, endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

struct GlassButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.system(.headline, design: .rounded))
            .padding(.vertical, 14).padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
        if prominent {
            label.foregroundStyle(Color.black)
                .background(Capsule().fill(Color.white))
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
        } else {
            label.foregroundStyle(Color.white)
                .glassCard(28)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
        }
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct GaugeBar: View {
    let title: String, value: Double, goal: Double, unit: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title); Spacer(); Text("\(Int(value)) / \(Int(goal)) \(unit)").foregroundStyle(.secondary) }
                .font(.caption.weight(.semibold))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(title == "Calories" ? Color(red: 1.0, green: 0.62, blue: 0.26) : title == "Protéines" ? Color(red: 0.42, green: 0.86, blue: 0.5) : Color.white).frame(width: g.size.width * min(1, value / max(goal, 1)))
                }
            }.frame(height: 8)
        }
    }
}

enum Haptic {
    static func tap() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warn() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

func timeString(_ minutes: Int) -> String { String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60) }
func fmtKg(_ v: Double) -> String { v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v) }
