import AVFoundation
import Combine

/// Lecture à voix haute : voix naturelle Gemini TTS, sinon meilleure voix française installée sur l'iPhone.
@MainActor
final class VoiceOut: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = VoiceOut()
    @Published private(set) var speakingID: UUID?
    private var player: AVAudioPlayer?
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    static func bestFrenchVoice() -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("fr") }
            .max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "fr-FR")
    }

    func speak(_ text: String, id: UUID, gemini: GeminiClient) async {
        stop()
        speakingID = id
        let clean = String(text.replacingOccurrences(of: "⚠️", with: "").prefix(700))
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        if let wav = await gemini.synthesizeSpeech(clean), speakingID == id, let p = try? AVAudioPlayer(data: wav) {
            player = p
            p.play()
            try? await Task.sleep(for: .seconds(p.duration + 0.3))
            if speakingID == id { speakingID = nil }
            return
        }
        guard speakingID == id else { return }
        let u = AVSpeechUtterance(string: clean)
        u.voice = Self.bestFrenchVoice()
        u.rate = 0.5
        synth.speak(u)
    }

    func stop() {
        player?.stop(); player = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        speakingID = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speakingID = nil }
    }
}
