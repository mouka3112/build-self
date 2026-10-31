import WidgetKit
import SwiftUI
import ActivityKit

// Cible : Widget Extension (cocher « Include Live Activity »). Ajoute aussi SelfBuildAttributes.swift à cette cible.
struct SelfBuildLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SelfBuildAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: icon(context.attributes.mode)).font(.title2)
                VStack(alignment: .leading) {
                    Text(context.state.title).font(.headline).lineLimit(1)
                    Text(context.state.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(timerInterval: range(context.state.endDate), countsDown: true)
                    .font(.title3.monospacedDigit().bold()).multilineTextAlignment(.trailing).frame(width: 80)
            }
            .padding()
            .foregroundStyle(.white)
            .activityBackgroundTint(.black)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: icon(context.attributes.mode)).font(.title2) }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: range(context.state.endDate), countsDown: true)
                        .monospacedDigit().frame(width: 70)
                }
                DynamicIslandExpandedRegion(.center) { Text(context.state.title).font(.headline).lineLimit(1) }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.subtitle).font(.caption).foregroundStyle(.secondary) }
            } compactLeading: {
                Image(systemName: icon(context.attributes.mode))
            } compactTrailing: {
                Text(timerInterval: range(context.state.endDate), countsDown: true).monospacedDigit().frame(width: 44)
            } minimal: {
                Image(systemName: icon(context.attributes.mode))
            }
        }
    }

    private func icon(_ mode: String) -> String { mode == "workout" ? "dumbbell.fill" : "scope" }
    private func range(_ end: Date) -> ClosedRange<Date> { Date.now...max(end, Date.now.addingTimeInterval(1)) }
}

@main
struct SelfBuildWidgetBundle: WidgetBundle {
    var body: some Widget { SelfBuildLiveActivity() }
}
