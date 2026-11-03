import SwiftUI
import MapKit
import CoreLocation
import AVFoundation
import Combine

@MainActor
final class RunTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = RunTracker()
    @Published var running = false
    @Published var distance = 0.0
    @Published var elapsed = 0
    @Published var route: [CLLocationCoordinate2D] = []
    @Published var coachLine = ""
    weak var gemini: GeminiClient?
    weak var store: AppStore?
    private let lm = CLLocationManager()
    private let synth = AVSpeechSynthesizer()
    private var last: CLLocation?
    private var timer: Timer?
    private var nextKm = 1
    private var lastCoachAt = 0

    override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyBest
        lm.activityType = .fitness
        lm.distanceFilter = 5
    }

    private var samples: [(t: Int, d: Double)] = []
    private var voicePlayer: AVAudioPlayer?

    func start() {
        distance = 0; elapsed = 0; route = []; last = nil; nextKm = 1; lastCoachAt = 0; coachLine = ""; samples = []
        lm.requestWhenInUseAuthorization()
        lm.allowsBackgroundLocationUpdates = true
        lm.pausesLocationUpdatesAutomatically = false
        lm.showsBackgroundLocationIndicator = true
        lm.startUpdatingLocation()
        MusicManager.shared.runMode = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        running = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        LiveActivityManager.shared.start(mode: "workout", title: "Course en cours", subtitle: "Coach Nexus actif", minutes: 90)
        coach("La course vient de démarrer : présente l'échauffement et choisis une première musique adaptée.")
    }

    func stop() {
        timer?.invalidate(); timer = nil
        lm.stopUpdatingLocation()
        lm.allowsBackgroundLocationUpdates = false
        running = false
        voicePlayer?.stop()
        synth.stopSpeaking(at: .immediate)
        if distance > 50, let store {
            let step = max(1, route.count / 300)
            let pts = route.enumerated().filter { $0.offset % step == 0 }
                .map { Coord(lat: $0.element.latitude, lon: $0.element.longitude) }
            store.engine.apply(.add(.runRecord(RunRecord(date: .now, distance: distance, duration: elapsed, route: pts))))
        }
        LiveActivityManager.shared.end()
        MusicManager.shared.duck(false)
        MusicManager.shared.runMode = false
        say("Bravo \(store?.firstName ?? ""), course terminée ! Étire-toi et bois de l'eau.")
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.handle(locations) }
    }

    private func handle(_ locs: [CLLocation]) {
        guard running else { return }
        for l in locs where l.horizontalAccuracy >= 0 && l.horizontalAccuracy < 30 {
            if let p = last {
                let d = l.distance(from: p)
                if d < 3 { continue }
                distance += d
            }
            last = l
            route.append(l.coordinate)
        }
    }

    private func tick() {
        elapsed += 1
        samples.append((elapsed, distance))
        if distance >= Double(nextKm) * 1000 {
            let km = nextKm; nextKm += 1
            coach("Il vient de terminer le kilomètre \(km).")
        } else if elapsed - lastCoachAt >= 180 {
            coach("Point régulier pendant la course.")
        }
    }

    private struct CoachReply: Decodable { let say: String; let track: String? }

    /// Allure sur la dernière minute (min/km) ou nil.
    private var recentPace: Int? {
        guard let old = samples.last(where: { $0.t <= elapsed - 60 }), distance - old.d > 20 else { return nil }
        return Int(60.0 / ((distance - old.d) / 1000))
    }

    private func fmtPace(_ s: Int?) -> String { s.map { String(format: "%d:%02d", $0 / 60, $0 % 60) } ?? "inconnue" }

    /// Coach IA : lit tes stats (distance, durée, allure récente vs moyenne), parle avec une voix naturelle et peut changer la musique.
    private func coach(_ reason: String) {
        lastCoachAt = elapsed
        let avg = distance > 50 ? Int(Double(elapsed) / (distance / 1000)) : nil
        let titles = MusicManager.shared.trackTitles
        let now = MusicManager.shared.current?.deletingPathExtension().lastPathComponent ?? "aucune"
        let fallback = ["Beau rythme, continue comme ça !", "Respire profondément, tu gères.",
                        "Chaque pas construit ta discipline.", "Reste régulier, tu es plus fort que tu ne le crois."].randomElement() ?? "Allez !"
        let prompt = """
        Tu es le coach de course vocal de \(store?.aiPersona ?? "l'utilisateur"), débutant. \(reason)
        Stats : distance \(String(format: "%.2f", distance / 1000)) km, temps \(elapsed / 60) min \(elapsed % 60) s, allure moyenne \(fmtPace(avg)) min/km, allure de la dernière minute \(fmtPace(recentPace)) min/km.
        Musiques disponibles : \(titles.isEmpty ? "aucune" : titles.joined(separator: " | ")). Musique actuelle : \(now).
        Adapte-toi : allure qui chute → relance avec une musique plus énergique ; trop vite au début → conseille de ralentir ; bon rythme → félicite.
        Réponds UNIQUEMENT en JSON : {"say": "1 à 2 phrases (max 30 mots), énergiques, tutoiement, sans émoji, avec un chiffre de ses stats", "track": "titre EXACT à lancer parmi la liste, ou null pour garder la musique actuelle"}
        """
        Task {
            var line = fallback
            var track: String? = nil
            if let g = gemini, let r = try? await g.json(CoachReply.self, prompt) { line = r.say; track = r.track }
            coachLine = line
            if let t = track, t.lowercased() != "null", !t.isEmpty, t != now { MusicManager.shared.play(title: t) }
            say(line)
        }
    }

    /// Voix naturelle Gemini si disponible, sinon meilleure voix française du système. La musique baisse pendant que le coach parle.
    private func say(_ text: String) {
        Task {
            MusicManager.shared.duck(true)
            if let g = gemini, let wav = await g.synthesizeSpeech(text), let p = try? AVAudioPlayer(data: wav) {
                voicePlayer = p
                p.volume = 1
                p.play()
                try? await Task.sleep(for: .seconds(p.duration + 0.3))
            } else {
                let u = AVSpeechUtterance(string: text)
                u.voice = bestFrenchVoice()
                u.rate = 0.52; u.pitchMultiplier = 1.08
                synth.speak(u)
                try? await Task.sleep(for: .seconds(Double(text.count) * 0.07 + 0.5))
            }
            MusicManager.shared.duck(false)
        }
    }

    private func bestFrenchVoice() -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("fr") }.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "fr-FR")
    }
}

struct RunningView: View {
    @ObservedObject private var tracker = RunTracker.shared
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var gemini: GeminiClient
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)

    private var pace: String {
        guard tracker.distance > 50 else { return "--:--" }
        let p = Int(Double(tracker.elapsed) / (tracker.distance / 1000))
        return String(format: "%d:%02d", p / 60, p % 60)
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 16) {
                    Map(position: $camera) {
                        UserAnnotation()
                        if tracker.route.count > 1 { MapPolyline(coordinates: tracker.route).stroke(.white, lineWidth: 5) }
                    }
                    .frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    HStack {
                        stat(String(format: "%.2f", tracker.distance / 1000), "km")
                        stat(String(format: "%d:%02d", tracker.elapsed / 60, tracker.elapsed % 60), "temps")
                        stat(pace, "min/km")
                    }
                    if !tracker.coachLine.isEmpty {
                        Label(tracker.coachLine, systemImage: "waveform").font(.callout).padding(14).frame(maxWidth: .infinity, alignment: .leading).glassCard(20)
                    }
                    Button {
                        if tracker.running { tracker.stop() } else {
                            tracker.gemini = gemini; tracker.store = store; tracker.start()
                        }
                        Haptic.tap()
                    } label: { Label(tracker.running ? "Terminer la course" : "Démarrer la course", systemImage: tracker.running ? "stop.fill" : "figure.run") }
                        .buttonStyle(GlassButtonStyle(prominent: true))
                    Text("Le coach Nexus lit ta vitesse et ton temps, te parle avec une voix naturelle (toutes les 3 min et à chaque km) et change ta musique importée selon ta forme.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)

                    if !store.runs.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Historique").font(.headline)
                            ForEach(store.runs.sorted { $0.date > $1.date }.prefix(10)) { r in
                                HStack {
                                    Text(r.date, format: .dateTime.day().month(.abbreviated))
                                    Spacer()
                                    Text(String(format: "%.2f km · %d min", r.distance / 1000, r.duration / 60)).monospacedDigit()
                                }
                                .contextMenu { Button("Supprimer", role: .destructive) { store.engine.apply(.delete(.runRecord(r.id))) } }
                            }
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard(24)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Running")
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(.title, design: .rounded).weight(.bold).monospacedDigit()).minimumScaleFactor(0.6).lineLimit(1)
            Text(l).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14).glassCard(20)
    }
}
