import WidgetKit
import SwiftUI
import ActivityKit

/// Nexus en verre noir & blanc, dessiné en SwiftUI (réutilisé partout dans la Live Activity).
struct NexusFace: View {
    let pose: String
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
            Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: max(1, size * 0.035))
            Capsule().fill(Color.white.opacity(0.35)).frame(width: size * 0.3, height: size * 0.06)
                .rotationEffect(.degrees(-30)).offset(x: -size * 0.17, y: -size * 0.28)
            eyes
            if pose == "wave" && size > 30 {
                Image(systemName: "hand.wave.fill").font(.system(size: size * 0.36)).foregroundStyle(.white)
                    .offset(x: size * 0.56, y: -size * 0.3)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private var eyes: some View {
        let dx: CGFloat = pose == "lookL" ? -size * 0.09 : pose == "lookR" ? size * 0.09 : 0
        if pose == "happy" {
            HStack(spacing: size * 0.2) { arc; arc }.offset(x: dx, y: size * 0.03)
        } else {
            HStack(spacing: size * 0.17) { eye; eye }.offset(x: dx)
        }
    }
    private var eye: some View {
        Capsule().fill(Color.white).frame(width: size * 0.095, height: pose == "blink" ? 2 : size * 0.21)
    }
    private var arc: some View {
        Circle().trim(from: 0.5, to: 1)
            .stroke(Color.white, style: StrokeStyle(lineWidth: size * 0.065, lineCap: .round))
            .frame(width: size * 0.15, height: size * 0.15)
    }
}

/// Gros compte à rebours (ou ✅ quand c'est terminé).
private struct Countdown: View {
    let state: SelfBuildAttributes.ContentState
    let fontSize: CGFloat
    let width: CGFloat

    var body: some View {
        if state.finished == true {
            Image(systemName: "checkmark.circle.fill").font(.system(size: fontSize, weight: .bold)).foregroundStyle(.white)
                .frame(width: width)
        } else {
            Text(timerInterval: Date.now...max(state.endDate, Date.now.addingTimeInterval(1)), countsDown: true)
                .font(.system(size: fontSize, weight: .bold, design: .rounded).monospacedDigit())
                .multilineTextAlignment(.trailing)
                .frame(width: width)
        }
    }
}

struct SelfBuildLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SelfBuildAttributes.self) { context in
            // Écran verrouillé / bannière : Nexus à gauche, titre, grand compte à rebours (comme Duolingo)
            HStack(spacing: 14) {
                NexusFace(pose: context.state.pose, size: 58)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.title).font(.headline).lineLimit(1)
                    Text(context.state.subtitle).font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                }
                Spacer(minLength: 4)
                Countdown(state: context.state, fontSize: 30, width: 96)
            }
            .padding(16)
            .foregroundStyle(.white)
            .activityBackgroundTint(Color(red: 0.05, green: 0.05, blue: 0.09))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { NexusFace(pose: context.state.pose, size: 46).padding(.leading, 4) }
                DynamicIslandExpandedRegion(.trailing) { Countdown(state: context.state, fontSize: 24, width: 84) }
                DynamicIslandExpandedRegion(.center) { Text(context.state.title).font(.headline).lineLimit(1) }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            } compactLeading: {
                NexusFace(pose: context.state.pose, size: 22)
            } compactTrailing: {
                if context.state.finished == true {
                    Image(systemName: "checkmark").foregroundStyle(.white)
                } else {
                    Text(timerInterval: Date.now...max(context.state.endDate, Date.now.addingTimeInterval(1)), countsDown: true)
                        .monospacedDigit().frame(width: 46)
                }
            } minimal: {
                NexusFace(pose: context.state.pose, size: 22)
            }
            .keylineTint(.white)
        }
    }
}

@main
struct SelfBuildWidgetBundle: WidgetBundle {
    var body: some Widget { SelfBuildLiveActivity() }
}
