import SwiftUI
import Combine
import Speech
import AVFoundation

/// Dictée vocale (français). Nécessite NSMicrophoneUsageDescription + NSSpeechRecognitionUsageDescription.
final class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() { isRecording ? stop() : start() }

    func start() {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { return }
            AVAudioApplication.requestRecordPermission { granted in
                guard granted else { return }
                DispatchQueue.main.async { self.begin() }
            }
        }
    }

    private nonisolated static func makeTap(_ req: SFSpeechAudioBufferRecognitionRequest) -> (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in req.append(buffer) }
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable, !engine.isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: Self.makeTap(req))
        engine.prepare()
        do { try engine.start() } catch { return }
        isRecording = true

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                if let result { self?.transcript = result.bestTranscription.formattedString }
                if error != nil || (result?.isFinal ?? false) { self?.stop() }
            }
        }
    }

    func stop() {
        if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
    }
}

/// Bouton micro réutilisable : écrit la dictée à la suite du texte existant.
struct DictationButton: View {
    @Binding var text: String
    @StateObject private var speech = SpeechRecognizer()
    @State private var base = ""

    var body: some View {
        Button {
            if !speech.isRecording { base = text; speech.transcript = "" }
            speech.toggle()
        } label: {
            Image(systemName: speech.isRecording ? "waveform.circle.fill" : "mic.fill")
                .font(.title2)
                .symbolEffect(.pulse, isActive: speech.isRecording)
                .frame(width: 44, height: 44)
        }
        .onChange(of: speech.transcript) { _, new in
            guard speech.isRecording else { return }
            text = base.isEmpty ? new : base + " " + new
        }
        .onChange(of: text) { _, new in
            if new.isEmpty && speech.isRecording { speech.stop() }
        }
    }
}
