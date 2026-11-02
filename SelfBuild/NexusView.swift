import SwiftUI

/// Chat avec Nexus : streaming mot par mot, mascotte vivante, dictée, photos,
/// et sous chaque réponse les actions RÉELLEMENT exécutées (avec Annuler / Appliquer).
struct NexusView: View {
    @EnvironmentObject var nexus: NexusSession
    @EnvironmentObject var gemini: GeminiClient
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var router: Router
    @ObservedObject private var voice = VoiceOut.shared
    @State private var input = ""
    @State private var attached: UIImage?
    @State private var showPicker = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    MascotView(thinking: nexus.busy, size: 80)
                        .frame(maxWidth: .infinity)
                    Menu {
                        Button { nexus.reset() } label: { Label("Nouvelle conversation", systemImage: "square.and.pencil") }
                        Button { router.go(.journal) } label: { Label("Journal Nexus", systemImage: AppDestination.journal.icon) }
                        Button { router.go(.settings) } label: { Label("Réglages IA", systemImage: "gearshape") }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title2).frame(width: 44, height: 44)
                    }
                    .padding(.trailing, 12)
                }
                .padding(.top, 4)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(nexus.messages) { m in
                                MessageBubble(message: m, isLast: m.id == nexus.messages.last?.id, busy: nexus.busy,
                                              speaking: voice.speakingID == m.id) {
                                    if voice.speakingID == m.id { voice.stop() }
                                    else { Task { await voice.speak(m.text, id: m.id, gemini: gemini) } }
                                }
                                .id(m.id)
                            }
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: nexus.messages.count) { _, _ in scrollDown(proxy) }
                    .onChange(of: nexus.messages.last?.text) { _, _ in scrollDown(proxy) }
                    .onAppear { scrollDown(proxy) }
                }
                inputBar
            }
        }
        .hideKeyboardOnTap()
        .photoPicker(isPresented: $showPicker) { attached = $0 }
    }

    private func scrollDown(_ proxy: ScrollViewProxy) {
        if let last = nexus.messages.last { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) } }
    }

    private var canSend: Bool {
        !nexus.busy && (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attached != nil)
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let img = attached {
                HStack {
                    Image(uiImage: img).resizable().scaledToFill().frame(width: 50, height: 50).clipShape(RoundedRectangle(cornerRadius: 10))
                    Text("Photo jointe").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { attached = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                }
                .padding(.horizontal, 20)
            }
            HStack(spacing: 4) {
                Button { showPicker = true } label: { Image(systemName: "camera.fill").font(.title3).frame(width: 40, height: 44) }
                DictationButton(text: $input)
                TextField(nexus.busy ? "Nexus réfléchit…" : "Dis-moi ce que tu as fait…", text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .onSubmit(send)
                Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.4)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .glassCard(30)
            .padding(.horizontal)
        }
        .padding(.bottom, 6)
    }

    private func send() {
        guard canSend else { return }
        nexus.send(input, image: attached)
        input = ""
        attached = nil
    }
}

private struct MessageBubble: View {
    @EnvironmentObject var store: AppStore
    let message: ChatMessage
    let isLast: Bool
    let busy: Bool
    let speaking: Bool
    let onSpeak: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            if message.isUser { Spacer(minLength: 50) }
            VStack(alignment: .leading, spacing: 8) {
                if let img = message.image {
                    Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: 200).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .foregroundStyle(message.isError ? Color(red: 1.0, green: 0.55, blue: 0.4) : (message.isUser ? Color.black : Color.white))
                        .textSelection(.enabled)
                } else if !message.isUser {
                    if isLast && busy {
                        HStack(spacing: 8) { ProgressView().tint(.white); Text("Nexus réfléchit…").font(.caption).foregroundStyle(.secondary) }
                    } else {
                        Text("…").foregroundStyle(.secondary)
                    }
                }
                if let jid = message.journalID, let e = store.journal.first(where: { $0.id == jid }) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(e.items) { it in JournalItemRow(entryID: e.id, item: it, compact: true) }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                if !message.isUser && !message.text.isEmpty && !(isLast && busy) {
                    Button(action: onSpeak) {
                        Image(systemName: speaking ? "stop.circle.fill" : "speaker.wave.2.fill").font(.caption)
                    }
                    .buttonStyle(PressStyle())
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background { if message.isUser { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white) } }
            .modifier(BubbleGlass(enabled: !message.isUser))
            if !message.isUser { Spacer(minLength: 30) }
        }
    }
}

private struct BubbleGlass: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.glassCard(20) } else { content }
    }
}
