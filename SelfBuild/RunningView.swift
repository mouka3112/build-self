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

    func start() {
        distance = 0; elapsed = 0; route = []; last = nil; nextKm = 1; lastCoachAt = 0; coachLine = ""
        lm.requestWhenInUseAuthorization()
        lm.allowsBackgroundLocationUpdates = true
        lm.pausesLocationUpdatesAutomatically = false
        lm.showsBackgroundLocationIndicator = true
        lm.startUpdatingLocation()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        running = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        speak("C'est parti Melik ! Trouve ton rythme et respire.")
        LiveActivityManager.shared.start(mode: "workout", title: "Course en cours", subtitle: "Coach vocal actif", minutes: 90)
    }

    func stop() {
        timer?.invalidate(); timer = nil
        lm.stopUpdatingLocation()
        lm.allowsBackgroundLocationUpdates = false
        running = false
        synth.stopSpeaking(at: .immediate)
        if distance > 50, let store {
            let step = max(1, route.count / 300)
            let pts = route.enumerated().filter { $0.offset % step == 0 }
                .map { Coord(lat: $0.element.latitude, lon: $0.element.longitude) }
            store.runs.append(RunRecord(date: .now, distance: distance, duration: elapsed, route: pts))
        }
        LiveActivityManager.shared.end()
        speak("Bravo, course terminée !")
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
        if distance >= Double(nextKm) * 1000 {
            let km = nextKm; nextKm += 1
            coach("Il vient de terminer le kilomètre \(km)")
        } else if elapsed - lastCoachAt >= 240 {
            coach("Encouragement en cours de route")
        }
    }

    private func coach(_ reason: String) {
        lastCoachAt = elapsed
        let pace = distance > 0 ? Int(Double(elapsed) / (distance / 1000)) : 0
        let fallback = ["Beau rythme, continue comme ça !", "Respire profondément, tu gères.",
                        "Chaque pas construit ta discipline.", "Reste régulier, tu es plus fort que tu ne le crois."].randomElement() ?? "Allez !"
        let prompt = """
        Tu es le coach vocal de Melik pendant sa course. \(reason). Distance \(String(format: "%.2f", distance / 1000)) km, temps \(elapsed / 60) min, allure \(pace / 60):\(String(format: "%02d", pace % 60)) min/km.
        Une seule phrase (max 20 mots), énergique, en français, tutoiement, sans émoji.
        """
        Task {
            var line = fallback
            if let g = gemini, let r = try? await g.text(prompt) { line = r }
            coachLine = line
            speak(line)
        }
    }

    private func speak(_ s: String) {
        let u = AVSpeechUtterance(string: s)
        u.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        u.rate = 0.5
        synth.speak(u)
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
                    Text("Le coach vocal parle à chaque kilomètre et toutes les 4 minutes (Nexus si la clé Gemini est configurée).")
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
                                .contextMenu { Button("Supprimer", role: .destructive) { store.runs.removeAll { $0.id == r.id } } }
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
