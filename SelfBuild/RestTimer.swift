import SwiftUI
import Combine

@MainActor
final class RestTimer: ObservableObject {
    @Published var remaining = 0
    private var task: Task<Void, Never>?

    func start(_ seconds: Int = 90) {
        task?.cancel()
        remaining = seconds
        NotificationManager.shared.schedule(id: "rest", title: "Repos terminé 💪", body: "Prochaine série.", in: TimeInterval(seconds))
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                if self.remaining <= 1 { self.remaining = 0; Haptic.success(); return }
                self.remaining -= 1
            }
        }
    }

    func add(_ seconds: Int) {
        guard remaining > 0 else { return }
        remaining += seconds
        NotificationManager.shared.schedule(id: "rest", title: "Repos terminé 💪", body: "Prochaine série.", in: TimeInterval(remaining))
    }

    func stop() {
        task?.cancel(); remaining = 0
        NotificationManager.shared.cancel(id: "rest")
    }
}

struct RestBar: View {
    @EnvironmentObject var rest: RestTimer
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "timer").font(.title2)
            Text(String(format: "%d:%02d", rest.remaining / 60, rest.remaining % 60))
                .font(.system(.title, design: .rounded).monospacedDigit().bold())
            Spacer()
            Button("+15 s") { rest.add(15) }.buttonStyle(PressStyle())
            Button("Passer") { rest.stop() }.buttonStyle(PressStyle()).fontWeight(.bold)
        }
        .padding(16).glassCard(28).padding(.horizontal).padding(.bottom, 4)
    }
}
