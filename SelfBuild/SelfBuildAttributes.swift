import ActivityKit
import Foundation

// ⚠️ Ce fichier doit être membre de la cible APP *et* de la cible WIDGET EXTENSION.
struct SelfBuildAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var subtitle: String
        var endDate: Date
        /// Pose de Nexus : idle, wave, lookL, lookR, blink, happy
        var pose: String = "idle"
    }
    var mode: String   // "focus" ou "workout"
}
