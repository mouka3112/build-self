import ActivityKit
import Foundation

// ⚠️ Ce fichier doit être membre de la cible APP *et* de la cible WIDGET EXTENSION (voir project.yml).
struct SelfBuildAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var subtitle: String
        var endDate: Date
        /// Pose de Nexus : idle, wave, lookL, lookR, blink, happy
        var pose: String = "idle"
        /// v3 : écran de fin (« Terminé ✅ ») au lieu du compte à rebours.
        var finished: Bool? = nil
    }
    var mode: String   // "focus", "workout", "run"
}
