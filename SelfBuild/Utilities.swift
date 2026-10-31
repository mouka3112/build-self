import SwiftUI
import UIKit
import SafariServices
import AVKit
import LocalAuthentication

// MARK: Photos (stockées localement dans l'app)
enum PhotoStore {
    static var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func save(_ image: UIImage) -> String? {
        let name = UUID().uuidString + ".jpg"
        guard let data = image.scaled(maxSide: 1600).jpegData(compressionQuality: 0.7) else { return nil }
        do { try data.write(to: dir.appendingPathComponent(name), options: .atomic); return name } catch { return nil }
    }
    static func load(_ name: String) -> UIImage? { UIImage(contentsOfFile: dir.appendingPathComponent(name).path) }
}

extension UIImage {
    func scaled(maxSide: CGFloat) -> UIImage {
        let k = min(1, maxSide / max(size.width, size.height))
        if k >= 1 { return self }
        let target = CGSize(width: size.width * k, height: size.height * k)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: target, format: fmt).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}

// MARK: Web (vidéos YouTube)
struct WebLink: Identifiable { let url: URL; var id: URL { url } }

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

func youtubeSearch(_ query: String) -> URL? {
    let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
    return URL(string: "https://www.youtube.com/results?search_query=\(q)")
}

// MARK: AirPlay
struct AirPlayPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView(); v.tintColor = .white; v.activeTintColor = .white; return v
    }
    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
}

// MARK: Face ID
enum Biometrics {
    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext(); var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return false }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

// MARK: Météo (Open-Meteo, sans clé) – Le Kef
struct Weather {
    let temp: Double, code: Int
    var summary: String {
        switch code {
        case 0: return "ciel dégagé"
        case 1, 2, 3: return "nuageux"
        case 45, 48: return "brouillard"
        case 51...67: return "pluie"
        case 71...77: return "neige"
        case 80...82: return "averses"
        case 95...99: return "orage"
        default: return "variable"
        }
    }
    var icon: String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2, 3: return "cloud.sun.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...67, 80...82: return "cloud.rain.fill"
        case 71...77: return "snowflake"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

enum WeatherService {
    private struct R: Decodable {
        struct C: Decodable { let temperature_2m: Double; let weather_code: Int }
        let current: C
    }
    static func fetch() async -> Weather? {
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=36.17&longitude=8.70&current=temperature_2m,weather_code"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let r = try? JSONDecoder().decode(R.self, from: data) else { return nil }
        return Weather(temp: r.current.temperature_2m, code: r.current.weather_code)
    }
}

// MARK: Bouton dynamique toujours présent
struct SmartButton: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var router: Router

    private var target: (dest: AppDestination, label: String) {
        if let a = router.aiTarget { return (a, "Nexus → \(a.title)") }
        guard let t = store.pending.first else { return (.nexus, "Demander à Nexus") }
        switch t.kind {
        case .workout: return (.muscu, "Séance")
        case .meal: return (.nutrition, "Repas")
        case .study: return (.study, "Étudier")
        case .school: return (.study, "Devoirs")
        case .hygiene: return (.hygiene, "Hygiène")
        case .rest: return (.running, "Bouger")
        case .sleep: return (.safe, "Journal du soir")
        case .other: return (.nexus, "Nexus")
        }
    }

    var body: some View {
        let t = target
        if t.dest.tabIndex != router.selectedTab {
            Button { Haptic.tap(); router.go(t.dest) } label: {
                HStack(spacing: 8) {
                    Image(systemName: t.dest.icon)
                    Text(t.label).lineLimit(1)
                }
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .glassCard(26)
            }
            .buttonStyle(PressStyle())
            .shadow(color: .white.opacity(0.15), radius: 12)
        }
    }
}

struct DestinationView: View {
    let dest: AppDestination
    var body: some View {
        switch dest {
        case .hub: HubView()
        case .nexus: NexusView()
        case .muscu: WorkoutView()
        case .nutrition: NutritionView()
        case .plus: PlusView()
        case .study: StudyView()
        case .finance: FinanceView()
        case .notes: NotesView()
        case .hygiene: HygieneView()
        case .wardrobe: WardrobeView()
        case .kitchen: KitchenView()
        case .music: MusicView()
        case .running: RunningView()
        case .projects: ProjectsView()
        case .challenges: ChallengesView()
        case .capsule: CapsuleView()
        case .reports: ReportsView()
        case .health: HealthView()
        case .safe: SafeSpaceView()
        case .settings: SettingsView()
        }
    }
}
