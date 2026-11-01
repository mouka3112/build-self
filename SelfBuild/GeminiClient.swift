import Foundation
import Combine
import UIKit

struct HomeworkCheck: Decodable { let valid: Bool; let validatedIndices: [Int]; let comment: String }
struct ReceiptResult: Decodable { let amount: Double; let category: String; let note: String }
struct Reminder: Decodable { let minute: Int; let title: String; let body: String }

@MainActor
final class GeminiClient: ObservableObject {
    @Published var isThinking = false
    private var inflight = 0 { didSet { isThinking = inflight > 0 } }

    /// Session dédiée : 120 s d'inactivité max, 3 min au total, attend le réseau au lieu d'échouer.
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 120
        c.timeoutIntervalForResource = 180
        c.waitsForConnectivity = true
        return URLSession(configuration: c)
    }()

    static let defaultModel = "gemini-3.8-flash"
    /// Modifiable dans Plus → Réglages si Google renomme le modèle.
    var modelName: String {
        let m = (UserDefaults.standard.string(forKey: "geminiModel") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return m.isEmpty ? Self.defaultModel : m
    }
    var apiKey: String { (UserDefaults.standard.string(forKey: "geminiKey") ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    enum GeminiError: LocalizedError {
        case noKey, bad(String)
        var errorDescription: String? {
            switch self {
            case .noKey: return "Ajoute ta clé Gemini dans Plus → Réglages."
            case .bad(let m): return m
            }
        }
    }

    // MARK: API publique
    private func chatContents(_ history: [ChatMessage]) -> [[String: Any]] {
        let msgs = Array(history.drop(while: { !$0.isUser }).suffix(10))
        let withImages = Set(msgs.filter { $0.image != nil }.suffix(1).map(\.id))
        return msgs.map { m -> [String: Any] in
            let t = String(m.text.prefix(1500))
            var parts: [[String: Any]] = [["text": t.isEmpty ? "(photo)" : t]]
            if withImages.contains(m.id), let b64 = m.image?.jpegBase64(maxSide: 1024) {
                parts.append(["inline_data": ["mime_type": "image/jpeg", "data": b64]])
            }
            return ["role": m.isUser ? "user" : "model", "parts": parts]
        }
    }

    /// Réponse complète d'un coup (non utilisée par le chat, qui est en streaming).
    func chat(history: [ChatMessage], store: AppStore) async throws -> String {
        try await generate(system: systemPrompt(store), contents: chatContents(history))
    }

    /// Chat en streaming : le texte arrive mot par mot via `onDelta` (réponse perçue beaucoup plus rapide).
    func streamChat(history: [ChatMessage], store: AppStore, onDelta: @escaping (String) -> Void) async throws {
        guard !apiKey.isEmpty else { throw GeminiError.noKey }
        let contents = chatContents(history)
        let system = systemPrompt(store)
        var attempt = 0
        var useThinking = true
        while true {
            do {
                let req = try makeRequest(stream: true, system: system, contents: contents, json: false, thinking: useThinking, maxTokens: 1500)
                inflight += 1
                defer { inflight -= 1 }
                let (bytes, resp) = try await session.bytes(for: req)
                guard let http = resp as? HTTPURLResponse else { throw GeminiError.bad("Réponse réseau invalide.") }
                if http.statusCode != 200 {
                    var body = ""
                    for try await l in bytes.lines { body += l; if body.count > 400 { break } }
                    if http.statusCode == 400, useThinking, body.lowercased().contains("thinking") { useThinking = false; continue }
                    if [429, 500, 503].contains(http.statusCode), attempt < 2 {
                        attempt += 1; try await Task.sleep(for: .seconds(Double(attempt) * 2)); continue
                    }
                    throw GeminiError.bad("Erreur Gemini \(http.statusCode) : \(body.prefix(180))")
                }
                var got = false
                for try await line in bytes.lines {
                    guard line.hasPrefix("data:") else { continue }
                    let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    guard let d = payload.data(using: .utf8), let r = try? JSONDecoder().decode(GenResponse.self, from: d) else { continue }
                    let t = r.candidates?.first?.content?.parts?.compactMap(\.text).joined() ?? ""
                    if !t.isEmpty { got = true; onDelta(t) }
                }
                if !got { throw GeminiError.bad("Réponse vide de Gemini.") }
                return
            } catch let e as URLError where (e.code == .timedOut || e.code == .networkConnectionLost) && attempt < 2 {
                attempt += 1
                try? await Task.sleep(for: .seconds(2))
                continue
            }
        }
    }

    /// Texte libre (avec photo optionnelle).
    func text(_ prompt: String, image: UIImage? = nil, store: AppStore? = nil) async throws -> String {
        var parts: [[String: Any]] = [["text": prompt]]
        if let b64 = image?.jpegBase64() { parts.append(["inline_data": ["mime_type": "image/jpeg", "data": b64]]) }
        return try await generate(system: store.map { systemPrompt($0) }, contents: [["role": "user", "parts": parts]])
    }

    /// Réponse JSON décodée dans le type voulu.
    func json<T: Decodable>(_ type: T.Type, _ prompt: String, image: UIImage? = nil, store: AppStore? = nil) async throws -> T {
        var parts: [[String: Any]] = [["text": prompt]]
        if let b64 = image?.jpegBase64() { parts.append(["inline_data": ["mime_type": "image/jpeg", "data": b64]]) }
        let t = try await generate(system: store.map { systemPrompt($0) }, contents: [["role": "user", "parts": parts]], json: true)
        return try decodeJSON(type, t)
    }

    func validateHomework(image: UIImage, pending: [Homework]) async throws -> HomeworkCheck {
        let list = pending.enumerated().map { "\($0.offset + 1). \($0.element.subject) – \($0.element.title)" }.joined(separator: "\n")
        let prompt = """
        Voici une photo envoyée par Melik, élève de 9ème année, pour prouver que ses devoirs sont faits.
        Devoirs à valider :
        \(list)
        Regarde la photo (cahier, feuille, exercices écrits). Réponds UNIQUEMENT en JSON :
        {"valid": bool, "validated_indices": [numéros des devoirs clairement faits sur la photo], "comment": "1-2 phrases en français, tutoiement, direct"}
        valid=false si la photo est floue, vide, sans travail visible, ou ne correspond à aucun devoir listé. Sois exigeant mais juste.
        """
        let text = try await generate(system: nil, contents: [imageContent(prompt, image)], json: true)
        return try decodeJSON(HomeworkCheck.self, text)
    }

    func scanReceipt(image: UIImage) async throws -> ReceiptResult {
        let cats = Finance.categories.map(\.name).joined(separator: ", ")
        let prompt = """
        Analyse ce ticket de caisse (Tunisie, montants en dinars tunisiens DT, souvent 3 décimales). Réponds UNIQUEMENT en JSON :
        {"amount": total TTC en nombre, "category": une valeur parmi [\(cats)], "note": "nom du magasin ou résumé court"}
        """
        let text = try await generate(system: nil, contents: [imageContent(prompt, image)], json: true)
        var r = try decodeJSON(ReceiptResult.self, text)
        if !Finance.categories.map(\.name).contains(r.category) { r = ReceiptResult(amount: r.amount, category: "Autre", note: r.note) }
        return r
    }

    func proactiveReminders(store: AppStore) async throws -> [Reminder] {
        let prompt = """
        Génère 3 à 5 rappels de notification pour le reste de la journée de Melik (discipline, devoirs, nutrition, sommeil), tous APRÈS \(timeString(store.minutesNow + 5)).
        Inclus au moins un rappel d'hygiène (dents, visage, cheveux ou douche) si ce n'est pas déjà fait.
        Réponds UNIQUEMENT en JSON : [{"minute": minutes depuis minuit (entier), "title": "max 5 mots", "body": "max 15 mots, direct, motivant"}]
        """
        let contents: [[String: Any]] = [["role": "user", "parts": [["text": prompt]]]]
        let text = try await generate(system: systemPrompt(store), contents: contents, json: true)
        return try decodeJSON([Reminder].self, text)
    }

    // MARK: Interne
    private func systemPrompt(_ s: AppStore) -> String {
        let df = DateFormatter(); df.locale = Locale(identifier: "fr_FR"); df.dateFormat = "EEEE d MMMM, HH:mm"
        let left = s.pending.map { "\(timeString($0.start)) \($0.title)" }.joined(separator: "; ")
        let hw = s.pendingHomework.map { "\($0.subject): \($0.title)" }.joined(separator: "; ")
        return """
        Tu es Nexus, le coach de vie intégré à SELF BUILD, l'app de Melik (15 ans, 1m83, 9ème année au collège pilote du Kef, Tunisie).
        Objectifs de Melik : discipline de fer (études + musculation), nutrition optimisée, gestion de l'argent de poche, autonomie.
        Style : français, tutoiement, direct, motivant, concis (max ~120 mots sauf si on te demande plus). Conseils adaptés à un adolescent :
        pas de régime extrême, pas de produits dopants, sommeil 8-9 h, technique avant charges.
        Contexte : \(df.string(from: .now)). Tâches restantes : \(left.isEmpty ? "aucune" : left).
        Nutrition du jour : \(Int(s.kcalToday))/\(Int(s.calorieGoal)) kcal, \(Int(s.proteinToday))/\(Int(s.proteinGoal)) g de protéines.
        Devoirs en attente : \(hw.isEmpty ? "aucun" : hw). Solde : \(String(format: "%.2f", s.balance)) TND.
        Hygiène du jour déjà faite : \(s.hygieneSummary). Rappelle gentiment dents, visage, cheveux, douche quand c'est pertinent.
        Goûts culinaires connus : \(s.tasteProfile.isEmpty ? "inconnus" : s.tasteProfile).
        Si utile, termine par UN tag [[GOTO:x]] (x parmi : muscu, nutrition, study, hygiene, wardrobe, kitchen, music, running, projects, challenges, capsule, reports, health, safe, finance, notes) pour ouvrir le bon module. Sinon, aucun tag.
        """
    }

    private func imageContent(_ prompt: String, _ image: UIImage) -> [String: Any] {
        var parts: [[String: Any]] = [["text": prompt]]
        if let b64 = image.jpegBase64() { parts.append(["inline_data": ["mime_type": "image/jpeg", "data": b64]]) }
        return ["role": "user", "parts": parts]
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        let clean = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase
        do { return try d.decode(T.self, from: Data(clean.utf8)) }
        catch { throw GeminiError.bad("Réponse IA illisible, réessaie.") }
    }

    private struct GenResponse: Decodable {
        struct Cand: Decodable {
            struct Content: Decodable { struct Part: Decodable { let text: String? }; let parts: [Part]? }
            let content: Content?
        }
        let candidates: [Cand]?
    }

    /// Gemini 3 réfléchit à fond par défaut (lent) : on demande un raisonnement léger.
    private func thinkingConfig() -> [String: Any]? {
        let m = modelName.lowercased()
        if m.contains("gemini-3") { return ["thinkingLevel": "low"] }
        if m.contains("2.5") && m.contains("flash") { return ["thinkingBudget": 0] }
        return nil
    }

    private func makeRequest(stream: Bool, system: String?, contents: [[String: Any]], json: Bool, thinking: Bool, maxTokens: Int) throws -> URLRequest {
        let method = stream ? "streamGenerateContent" : "generateContent"
        var comps = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):\(method)")!
        var items = [URLQueryItem(name: "key", value: apiKey)]
        if stream { items.append(URLQueryItem(name: "alt", value: "sse")) }
        comps.queryItems = items
        var gen: [String: Any] = ["maxOutputTokens": maxTokens]
        if json { gen["responseMimeType"] = "application/json" }
        if thinking, let t = thinkingConfig() { gen["thinkingConfig"] = t }
        var body: [String: Any] = ["contents": contents, "generationConfig": gen]
        if let system { body["systemInstruction"] = ["parts": [["text": system]]] }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private func generate(system: String?, contents: [[String: Any]], json: Bool = false) async throws -> String {
        guard !apiKey.isEmpty else { throw GeminiError.noKey }
        var attempt = 0
        var useThinking = true
        while true {
            do {
                let req = try makeRequest(stream: false, system: system, contents: contents, json: json, thinking: useThinking, maxTokens: 2000)
                inflight += 1
                defer { inflight -= 1 }
                let (data, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse else { throw GeminiError.bad("Réponse réseau invalide.") }
                if http.statusCode != 200 {
                    let msg = String(data: data, encoding: .utf8) ?? ""
                    if http.statusCode == 400, useThinking, msg.lowercased().contains("thinking") { useThinking = false; continue }
                    if [429, 500, 503].contains(http.statusCode), attempt < 2 {
                        attempt += 1; try await Task.sleep(for: .seconds(Double(attempt) * 2)); continue
                    }
                    throw GeminiError.bad("Erreur Gemini \(http.statusCode) : \(msg.prefix(180))")
                }
                let r = try JSONDecoder().decode(GenResponse.self, from: data)
                let text = r.candidates?.first?.content?.parts?.compactMap(\.text).joined() ?? ""
                if text.isEmpty { throw GeminiError.bad("Réponse vide de Gemini.") }
                return text
            } catch let e as URLError where (e.code == .timedOut || e.code == .networkConnectionLost) && attempt < 2 {
                attempt += 1
                try? await Task.sleep(for: .seconds(2))
                continue
            }
        }
    }
}

extension UIImage {
    func jpegBase64(maxSide: CGFloat = 1280) -> String? {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: target, format: fmt).image { _ in
            self.draw(in: CGRect(origin: .zero, size: target))
        }
        return img.jpegData(compressionQuality: 0.7)?.base64EncodedString()
    }
}
