import Foundation
import Combine
import UIKit

struct HomeworkCheck: Decodable { let valid: Bool; let validatedIndices: [Int]; let comment: String }
struct ReceiptResult: Decodable { let amount: Double; let category: String; let note: String }
struct Reminder: Decodable { let minute: Int; let title: String; let body: String }

@MainActor
final class GeminiClient: ObservableObject {
    @Published var isThinking = false

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
    func chat(history: [ChatMessage], store: AppStore) async throws -> String {
        let msgs = Array(history.drop(while: { !$0.isUser }).suffix(20))
        let withImages = Set(msgs.filter { $0.image != nil }.suffix(2).map(\.id))
        let contents: [[String: Any]] = msgs.map { m -> [String: Any] in
            var parts: [[String: Any]] = [["text": m.text.isEmpty ? "(photo)" : m.text]]
            if withImages.contains(m.id), let b64 = m.image?.jpegBase64() {
                parts.append(["inline_data": ["mime_type": "image/jpeg", "data": b64]])
            }
            return ["role": m.isUser ? "user" : "model", "parts": parts]
        }
        return try await generate(system: systemPrompt(store), contents: contents)
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

    private func generate(system: String?, contents: [[String: Any]], json: Bool = false) async throws -> String {
        guard !apiKey.isEmpty else { throw GeminiError.noKey }
        var comps = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent")!
        comps.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        var body: [String: Any] = ["contents": contents]
        if let system { body["systemInstruction"] = ["parts": [["text": system]]] }
        if json { body["generationConfig"] = ["responseMimeType": "application/json"] }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        isThinking = true
        defer { isThinking = false }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw GeminiError.bad("Réponse réseau invalide.") }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw GeminiError.bad("Erreur Gemini \(http.statusCode) : \(msg.prefix(180))")
        }
        let r = try JSONDecoder().decode(GenResponse.self, from: data)
        let text = r.candidates?.first?.content?.parts?.compactMap(\.text).joined() ?? ""
        if text.isEmpty { throw GeminiError.bad("Réponse vide de Gemini.") }
        return text
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
