import ActivityKit
import Combine
import Foundation

@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()
    @Published private(set) var isActive = false

    func start(mode: String, title: String, subtitle: String, minutes: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let end = Date().addingTimeInterval(Double(max(minutes, 1)) * 60)
        let state = SelfBuildAttributes.ContentState(title: title, subtitle: subtitle, endDate: end)
        Task {
            await endAll()
            do {
                _ = try Activity.request(attributes: SelfBuildAttributes(mode: mode),
                                         content: ActivityContent(state: state, staleDate: end),
                                         pushType: nil)
                isActive = true
            } catch {
                print("Live Activity impossible : \(error.localizedDescription)")
            }
        }
    }

    func end() { Task { await endAll() } }

    private func endAll() async {
        for a in Activity<SelfBuildAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        isActive = false
    }
}
