import SwiftUI

struct NexusView: View {
    @EnvironmentObject var gemini: GeminiClient
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var router: Router
    @State private var messages = [ChatMessage(isUser: false, text: "Salut Melik 👋 Je suis Nexus. Dis-moi ce dont tu as besoin.")]
    @State private var input = ""
    @State private var attached: UIImage?
    @State private var showPicker = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                MascotView(thinking: gemini.isThinking, size: 90).padding(.top, 8)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(messages) { m in bubble(m).id(m.id) }
                        }.padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                inputBar
            }
        }
        .hideKeyboardOnTap()
        .photoPicker(isPresented: $showPicker) { attached = $0 }
        .onAppear {
            if let p = router.pendingPrompt { router.pendingPrompt = nil; send(p) }
        }
    }

    private func bubble(_ m: ChatMessage) -> some View {
        HStack {
            if m.isUser { Spacer(minLength: 50) }
            VStack(alignment: .leading, spacing: 6) {
                if let img = m.image {
                    Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: 200).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                if !m.text.isEmpty { Text(m.text) } else if !m.isUser { ProgressView().tint(.white) }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(m.isUser ? Color.black : Color.white)
            .background { if m.isUser { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white) } }
            .modifier(BubbleGlass(enabled: !m.isUser))
            if !m.isUser { Spacer(minLength: 50) }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let img = attached {
                HStack {
                    Image(uiImage: img).resizable().scaledToFill().frame(width: 50, height: 50).clipShape(RoundedRectangle(cornerRadius: 10))
                    Text("Photo jointe").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { attached = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                }.padding(.horizontal, 20)
            }
            HStack(spacing: 4) {
                Button { showPicker = true } label: { Image(systemName: "camera.fill").font(.title3).frame(width: 40, height: 44) }
                DictationButton(text: $input)
                TextField("Parle à Nexus…", text: $input, axis: .vertical).lineLimit(1...4).submitLabel(.send)
                    .onSubmit { send(input) }
                Button { send(input) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .disabled((input.trimmingCharacters(in: .whitespaces).isEmpty && attached == nil) || gemini.isThinking)
            }
            .padding(.horizontal, 10).padding(.vertical, 6).glassCard(30).padding(.horizontal)
        }
        .padding(.bottom, 6)
    }

    private func send(_ text: String) {
        guard !gemini.isThinking else { return }          // une seule requête à la fois
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty || attached != nil else { return }
        messages.append(ChatMessage(isUser: true, text: t, image: attached))
        input = ""; attached = nil
        let history = messages                             // sans la bulle vide de réponse
        messages.append(ChatMessage(isUser: false, text: ""))
        let idx = messages.count - 1
        Task {
            do {
                try await gemini.streamChat(history: history, store: store) { delta in
                    messages[idx].text += delta
                }
                var r = messages[idx].text
                if let range = r.range(of: #"\[\[GOTO:([a-z]+)\]\]"#, options: .regularExpression) {
                    let tag = String(r[range]).replacingOccurrences(of: "[[GOTO:", with: "").replacingOccurrences(of: "]]", with: "")
                    if let dest = AppDestination(rawValue: tag), dest != .nexus { router.aiTarget = dest }
                    r = r.replacingOccurrences(of: #"\[\[GOTO:[a-z]+\]\]"#, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    messages[idx].text = r
                }
            } catch {
                messages[idx].text = "⚠️ \(error.localizedDescription)"
            }
        }
    }
}

private struct BubbleGlass: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.glassCard(20) } else { content }
    }
}
