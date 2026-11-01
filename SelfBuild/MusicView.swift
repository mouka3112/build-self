import SwiftUI
import AVFoundation
import Combine
import UniformTypeIdentifiers

/// Bruits blancs / ambiance générés en direct (aucun fichier nécessaire, fonctionne hors-ligne).
final class NoiseGenerator {
    enum Kind: String, CaseIterable, Identifiable {
        case white = "Blanc", soft = "Pluie douce", deep = "Grondement"
        var id: String { rawValue }
    }
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private(set) var running = false

    func start(_ kind: Kind) {
        stop()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        var last: Float = 0
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(bufferList)
            for frame in 0..<Int(frameCount) {
                let white = Float.random(in: -1...1)
                var v: Float
                switch kind {
                case .white: v = white * 0.5
                case .soft: last += 0.15 * (white - last); v = last * 1.2
                case .deep: last = (last + 0.02 * white) / 1.02; v = last * 6
                }
                v = max(-1, min(1, v))
                for buf in abl {
                    if let p = buf.mData?.assumingMemoryBound(to: Float.self) { p[frame] = v }
                }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
        do { try engine.start(); running = true } catch { print("Bruit impossible : \(error)") }
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        if let n = sourceNode { engine.detach(n) }
        sourceNode = nil; running = false
    }

    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }
}

final class MusicManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = MusicManager()
    @Published var tracks: [URL] = []
    @Published var current: URL?
    @Published var isPlaying = false
    @Published var noiseOn = false
    @Published var noiseKind = NoiseGenerator.Kind.soft
    @Published var noiseVolume: Float = 0.6 { didSet { noise.volume = noiseVolume } }
    private var player: AVAudioPlayer?
    private let noise = NoiseGenerator()

    static var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Music", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    override init() { super.init(); reload() }

    private func activateSession() {
        // .longFormAudio + sans mixWithOthers : requis pour que le routage AirPlay (HomePod, Apple TV, enceintes) fonctionne.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func reload() {
        let exts = ["mp3", "m4a", "wav", "aac", "flac", "aiff", "caf"]
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.dir, includingPropertiesForKeys: nil)) ?? []
        tracks = files.filter { exts.contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func importFiles(_ urls: [URL]) {
        for u in urls {
            let ok = u.startAccessingSecurityScopedResource()
            defer { if ok { u.stopAccessingSecurityScopedResource() } }
            let dest = Self.dir.appendingPathComponent(u.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: u, to: dest)
        }
        reload()
    }

    func delete(_ url: URL) {
        if current == url { player?.stop(); current = nil; isPlaying = false }
        try? FileManager.default.removeItem(at: url); reload()
    }

    func play(_ url: URL) {
        activateSession()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.play()
        current = url; isPlaying = player != nil
    }

    func toggle() {
        guard let p = player else { if let f = tracks.first { play(f) }; return }
        if p.isPlaying { p.pause(); isPlaying = false } else { p.play(); isPlaying = true }
    }

    func next() {
        guard !tracks.isEmpty else { return }
        let i = current.flatMap { tracks.firstIndex(of: $0) } ?? -1
        play(tracks[(i + 1) % tracks.count])
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.next() }
    }

    func startNoise(_ kind: NoiseGenerator.Kind? = nil) {
        activateSession()
        if let kind { noiseKind = kind }
        noise.start(noiseKind); noise.volume = noiseVolume; noiseOn = noise.running
    }
    func stopNoise() { noise.stop(); noiseOn = false }
}

struct MusicView: View {
    @ObservedObject private var music = MusicManager.shared
    @AppStorage("autoNoise") private var autoNoise = true
    @State private var showImporter = false

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        Text(music.current?.deletingPathExtension().lastPathComponent ?? "Aucun titre").font(.headline).lineLimit(1)
                        HStack(spacing: 30) {
                            Button { music.toggle() } label: { Image(systemName: music.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 54)) }
                            Button { music.next() } label: { Image(systemName: "forward.fill").font(.title) }
                            AirPlayButton()
                        }
                    }
                    .frame(maxWidth: .infinity).padding(20).glassCard(28)

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Bruits d'ambiance (hors-ligne)", systemImage: "waveform").font(.headline)
                        Picker("Type", selection: $music.noiseKind) {
                            ForEach(NoiseGenerator.Kind.allCases) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                        Slider(value: $music.noiseVolume, in: 0.05...1)
                        Button { music.noiseOn ? music.stopNoise() : music.startNoise() } label: {
                            Label(music.noiseOn ? "Arrêter" : "Lancer", systemImage: music.noiseOn ? "stop.fill" : "play.fill")
                        }.buttonStyle(GlassButtonStyle(prominent: true))
                        Toggle("Lancer automatiquement en mode Lockdown", isOn: $autoNoise).font(.subheadline)
                    }
                    .padding(16).glassCard(24)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Ma musique").font(.headline); Spacer()
                            Button { showImporter = true } label: { Label("Importer", systemImage: "square.and.arrow.down") }
                        }
                        if music.tracks.isEmpty { Text("Importe des fichiers audio (mp3, m4a, wav…) depuis l'app Fichiers.").font(.caption).foregroundStyle(.secondary) }
                        ForEach(music.tracks, id: \.self) { t in
                            Button { music.play(t) } label: {
                                HStack {
                                    Image(systemName: music.current == t ? "speaker.wave.2.fill" : "music.note")
                                    Text(t.deletingPathExtension().lastPathComponent).lineLimit(1)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu { Button("Supprimer", role: .destructive) { music.delete(t) } }
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard(24)
                }
                .padding()
            }
        }
        .navigationTitle("Musique & focus")
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r { music.importFiles(urls) }
        }
    }
}
