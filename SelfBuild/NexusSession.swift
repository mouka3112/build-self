import Foundation
import Combine
import UIKit

/// Conversation avec Nexus, partagée par toute l'app (Hub, onglet Nexus, boutons « Demander à Nexus »).
/// Pipeline d'un tour : contexte frais → Gemini (texte + appels de fonctions) → validation → ActionEngine → Journal.
@MainActor
final class NexusSession: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published private(set) var busy = false

    let store: AppStore
    let gemini: GeminiClient
    let router: Router
    /// Message envoyé pendant qu'un autre tour est en cours : il part juste après (jamais perdu).
    private var queued: (text: String, image: UIImage?)?

    init(store: AppStore, gemini: GeminiClient, router: Router) {
        self.store = store
        self.gemini = gemini
        self.router = router
        messages = [greeting()]
    }

    private func greeting() -> ChatMessage {
        ChatMessage(isUser: false, text: "Salut \(store.displayName) 👋 Je suis Nexus. Dis-moi ce que tu as fait ou ce dont tu as besoin : je mets l'app à jour pour toi.")
    }

    func reset() {
        guard !busy else { return }
        messages = [greeting()]
    }

    func send(_ text: String, image: UIImage? = nil) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty || image != nil else { return }
        if busy { queued = (t, image); return }
        messages.append(ChatMessage(isUser: true, text: t, image: image))
        let history = modelHistory()
        let reply = ChatMessage(isUser: false, text: "")
        messages.append(reply)
        busy = true
        Task { await self.run(history: history, replyID: reply.id, userText: t.isEmpty ? "(photo)" : t) }
    }

    /// Historique envoyé au modèle : chaque réponse de Nexus est suivie des actions réellement exécutées.
    private func modelHistory() -> [ChatMessage] {
        messages.map { m -> ChatMessage in
            guard !m.isUser, let jid = m.journalID, let e = store.journal.first(where: { $0.id == jid }) else { return m }
            let acts = e.items.map { "\($0.status.rawValue): \($0.summary)" }.joined(separator: " | ")
            var copy = ChatMessage(isUser: false, text: m.text + (acts.isEmpty ? "" : "\n[Actions app : \(acts)]"), image: m.image)
            copy.isError = m.isError
            return copy
        }.filter { !$0.isError }
    }

    private func index(of id: UUID) -> Int? { messages.firstIndex { $0.id == id } }

    private func run(history: [ChatMessage], replyID: UUID, userText: String) async {
        do {
            let turn = try await gemini.chatTurn(history: history,
                                                 system: AIContext.systemPrompt(store, tools: true),
                                                 tools: NexusTools.declarations()) { [weak self] delta in
                guard let self, let i = self.index(of: replyID) else { return }
                self.messages[i].text += delta
            }
            let planned = turn.calls.map { NexusTools.plan($0) }
            let entry = store.engine.perform(planned, userText: userText, aiText: turn.text)
            if let i = index(of: replyID) {
                messages[i].text = entry.aiText ?? turn.text
                messages[i].journalID = entry.items.isEmpty ? nil : entry.id
            }
            if let dest = entry.items.last(where: { $0.status == .applied && isNavigation($0.action) })?.destination, dest != .nexus {
                router.aiTarget = dest
            }
            if entry.items.contains(where: { $0.status == .applied }) { Haptic.success() }
            else if entry.items.contains(where: { $0.status == .rejected }) { Haptic.warn() }
        } catch {
            let msg = error.localizedDescription
            if let i = index(of: replyID) {
                messages[i].text = "⚠️ \(msg)"
                messages[i].isError = true
            }
            store.recordNexusError(userText: userText, message: msg)
            Haptic.warn()
        }
        busy = false
        if let q = queued {
            queued = nil
            send(q.text, image: q.image)
        }
    }

    private func isNavigation(_ a: AppAction?) -> Bool {
        if case .navigate? = a { return true }
        return false
    }
}
