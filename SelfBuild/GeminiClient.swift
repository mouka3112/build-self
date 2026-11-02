import Foundation
import Combine
import UIKit

struct HomeworkCheck: Decodable { let valid: Bool; let validatedIndices: [Int]; let comment: String }
struct ReceiptResult: Decodable { let amount: Double; let category: String; let note: String }
struct Reminder: Decodable { let minute: Int; let title: String; let body: String }

/// Résultat d'un tour de chat : le texte (déjà affiché mot par mot) + les appels de fonctions typés.
struct ChatTurn {
    var text: String
    var calls: [ToolCall]
    var model: String
}

@MainActor
final class GeminiClient: ObservableObject {
    @Published var isThinking = false
    @Published var activeModel = ""
    private var inflight = 0 { didSet { isThinking = inflight > 0 } }

    /// Session dédiée : pas d'attente infinie, chaque tentative est limitée à 40 s.
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 40
        c.timeoutIntervalForResource = 120
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    static let defaultModel = "gemini-3.8-flash"
    /// Modifiable dans Réglages si Google renomme le modèle.
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

    // MARK: Test de la clé (premier lancement)
    func testKey(_ key: String) async -> (ok: Bool, message: String) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return (false, "Colle d'abord ta clé.") }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200&key=\(k)") else {
            return (false, "Clé illisible (caractères invalides).")
        }
        do {
            let (data, resp) = try await session.data(from: url)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 {
                let n = (try? JSONDecoder().decode(ModelList.self, from: data))?.models.count ?? 0
                return (true, "✅ Clé valide — \(n) modèles disponibles.")
            }
            return (false, Self.readable(code: code, body: String(data: data, encoding: .utf8) ?? ""))
        } catch {
            return (false, "Pas de connexion : \(error.localizedDescription)")
        }
    }

    // MARK: Modèles de secours (503 « forte demande » / 429 / 404…)
    private struct ModelList: Decodable {
        struct M: Decodable { let name: String; let supportedGenerationMethods: [String]? }
        let models: [M]
    }
    private var cachedModels: [String] = []
    private var cachedFor = ""
    private var ttsModel: String?
    @Published private(set) var availableModels: [String] = []

    private func candidates() async -> [String] {
        if cachedFor == modelName + apiKey.suffix(4), !cachedModels.isEmpty { return cachedModels }
        var list = [modelName]
        if let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200&key=\(apiKey)"),
           let (data, _) = try? await session.data(from: url),
           let r = try? JSONDecoder().decode(ModelList.self, from: data) {
            let names = r.models.filter { ($0.supportedGenerationMethods ?? []).contains("generateContent") }
                .map { $0.name.replacingOccurrences(of: "models/", with: "") }
            ttsModel = names.first { $0.contains("tts") && $0.contains("flash") } ?? names.first { $0.contains("tts") }
            let bad = ["image", "tts", "audio", "live", "embedding", "robotics", "computer", "vision", "imagen", "veo", "learnlm", "gemma", "aqa", "native"]
            let flash = names.filter { n in n.contains("flash") && !bad.contains { n.contains($0) } }
            availableModels = flash.sorted(by: >)
            let lite = flash.filter { $0.contains("lite") }.sorted(by: >)
            let rest = flash.filter { !$0.contains("lite") }.sorted(by: >)
            for m in rest.prefix(2) + lite.prefix(2) where !list.contains(m) { list.append(m) }
        }
        for alias in ["gemini-flash-latest", "gemini-flash-lite-latest"] where !list.contains(alias) { list.append(alias) }
        cachedModels = Array(list.prefix(6)); cachedFor = modelName + apiKey.suffix(4)
        return cachedModels
    }

    // MARK: Messages lisibles
    static func readable(code: Int, body: String) -> String {
        let b = body.lowercased()
        switch code {
        case 400 where b.contains("api key") || b.contains("api_key"): return "Clé API invalide : vérifie-la dans Réglages."
        case 400: return "Requête refusée par Gemini (400)."
        case 401, 403: return "Clé refusée par Google (403) : API Gemini non activée pour cette clé ?"
        case 404: return "Modèle introuvable (404)."
        case 429: return "Quota Gemini atteint (429) : attends une minute."
        case 500, 502, 504: return "Erreur serveur Google (\(code))."
        case 503: return "Gemini est surchargé (503 : forte demande)."
        default: return "Erreur Gemini \(code)."
        }
    }

    // MARK: Historique court (10 messages, 1500 caractères, une seule image récente)
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

    // MARK: API publique (modules)
    /// Texte libre (avec photo optionnelle).
    func text(_ prompt: String, image: UIImage? = nil, store: AppStore? = nil) async throws -> String {
        var parts: [[String: Any]] = [["text": prompt]]
        if let b64 = image?.jpegBase64() { parts.append(["inline_data": ["mime_type": "image/jpeg", "data": b64]]) }
        return try await generate(system: store.map { AIContext.systemPrompt($0, tools: false) }, contents: [["role": "user", "parts": parts]])
    }

    /// Texte avec plusieurs photos (cours).
    func text(_ prompt: String, images: [UIImage], store: AppStore? = nil) async throws -> String {
        var parts: [[String: Any]] = [["text": prompt]]
        for img in images.prefix(4) { if let b64 = img.jpegBase64() { parts.append(["inline_data": ["mime_type": "image/jpeg", "data": b64]]) } }
        return try await generate(system: store.map { AIContext.systemPrompt($0, tools: false) }, contents: [["role": "user", "parts": parts]])
    }

    /// Réponse JSON (non streaming) décodée dans le type voulu.
    func json<T: Decodable>(_ type: T.Type, _ prompt: String, image: UIImage? = nil, store: AppStore? = nil) async throws -> T {
        var parts: [[String: Any]] = [["text": prompt]]
        if let b64 = image?.jpegBase64() { parts.append(["inline_data": ["mime_type": "image/jpeg", "data": b64]]) }
        let t = try await generate(system: store.map { AIContext.systemPrompt($0, tools: false) }, contents: [["role": "user", "parts": parts]], json: true)
        return try decodeJSON(type, t)
    }

    func validateHomework(image: UIImage, pending: [Homework], name: String = "l'élève") async throws -> HomeworkCheck {
        let list = pending.enumerated().map { "\($0.offset + 1). \($0.element.subject) – \($0.element.title)" }.joined(separator: "\n")
        let prompt = """
        Voici une photo envoyée par \(name) pour prouver que ses devoirs sont faits.
        Devoirs à valider :
        \(list)
        Regarde la photo (cahier, feuille, exercices écrits). Réponds UNIQUEMENT en JSON :
        {"valid": bool, "validated_indices": [numéros des devoirs clairement faits sur la photo], "comment": "1-2 phrases en français, tutoiement, direct"}
        valid=false si la photo est floue, vide, sans travail visible, ou ne correspond à aucun devoir listé. Sois exigeant mais juste.
        """
        return try await json(HomeworkCheck.self, prompt, image: image)
    }

    func scanReceipt(image: UIImage) async throws -> ReceiptResult {
        let cats = Finance.categoryNames.joined(separator: ", ")
        let prompt = """
        Analyse ce ticket de caisse (Tunisie, montants souvent à 3 décimales). Réponds UNIQUEMENT en JSON :
        {"amount": total TTC en nombre, "category": une valeur parmi [\(cats)], "note": "nom du magasin ou résumé court"}
        """
        var r = try await json(ReceiptResult.self, prompt, image: image)
        if !Finance.categoryNames.contains(r.category) { r = ReceiptResult(amount: r.amount, category: "Autre", note: r.note) }
        return r
    }

    func proactiveReminders(store: AppStore) async throws -> [Reminder] {
        let prompt = """
        Génère 3 à 5 rappels de notification pour le reste de la journée de \(store.displayName) (discipline, devoirs, nutrition, sommeil), tous APRÈS \(timeString(store.minutesNow + 5)).
        Inclus au moins un rappel d'hygiène (dents, visage, cheveux ou douche) si ce n'est pas déjà fait.
        Réponds UNIQUEMENT en JSON : [{"minute": minutes depuis minuit (entier), "title": "max 5 mots avec un emoji", "body": "max 15 mots, direct, motivant"}]
        """
        return try await json([Reminder].self, prompt, store: store)
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        let clean = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase
        do { return try d.decode(T.self, from: Data(clean.utf8)) }
        catch { throw GeminiError.bad("Réponse IA illisible, réessaie.") }
    }

    // MARK: Réseau
    /// Gemini 3 réfléchit à fond par défaut (lent) : on demande un raisonnement léger.
    private func thinkingConfig(_ model: String) -> [String: Any]? {
        let m = model.lowercased()
        if m.contains("gemini-3") || m.hasSuffix("-latest") { return ["thinkingLevel": "low"] }
        if m.contains("2.5") && m.contains("flash") { return ["thinkingBudget": 0] }
        return nil
    }

    private func makeRequest(model: String, stream: Bool, system: String?, contents: [[String: Any]], json: Bool,
                             thinking: Bool, maxTokens: Int, tools: [[String: Any]]? = nil) throws -> URLRequest {
        let method = stream ? "streamGenerateContent" : "generateContent"
        guard var comps = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):\(method)") else {
            throw GeminiError.bad("Nom de modèle invalide : \(model)")
        }
        var items = [URLQueryItem(name: "key", value: apiKey)]
        if stream { items.append(URLQueryItem(name: "alt", value: "sse")) }
        comps.queryItems = items
        guard let url = comps.url else { throw GeminiError.bad("Adresse Gemini invalide.") }
        var gen: [String: Any] = ["maxOutputTokens": maxTokens]
        if json { gen["responseMimeType"] = "application/json" }
        if thinking, let t = thinkingConfig(model) { gen["thinkingConfig"] = t }
        var body: [String: Any] = ["contents": contents, "generationConfig": gen]
        if let system { body["systemInstruction"] = ["parts": [["text": system]]] }
        if let tools, !tools.isEmpty {
            body["tools"] = [["functionDeclarations": tools]]
            body["toolConfig"] = ["functionCallingConfig": ["mode": "AUTO"]]
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 40
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private enum Outcome { case ok, dropThinking, nextModel(Int, String), fail(Int, String) }
    private func classify(_ code: Int, _ body: String, useThinking: Bool) -> Outcome {
        if code == 200 { return .ok }
        if code == 400, useThinking, body.lowercased().contains("thinking") { return .dropThinking }
        if [404, 429, 500, 502, 503, 504].contains(code) { return .nextModel(code, body) }
        return .fail(code, body)
    }

    /// Extrait le texte et les appels de fonctions d'une réponse (complète ou morceau SSE).
    private func parseParts(_ data: Data) -> (text: String, calls: [ToolCall]) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cands = root["candidates"] as? [[String: Any]],
              let content = cands.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { return ("", []) }
        var text = ""
        var calls: [ToolCall] = []
        for p in parts {
            if (p["thought"] as? Bool) == true { continue }
            if let t = p["text"] as? String { text += t }
            if let fc = p["functionCall"] as? [String: Any], let name = fc["name"] as? String {
                let args = (fc["args"] as? [String: Any] ?? [:]).mapValues { JSONValue($0) }
                calls.append(ToolCall(name: name, args: args))
            }
        }
        return (text, calls)
    }

    private func failureMessage(_ last: (code: Int, body: String)?, tried: [String]) -> String {
        guard let last else { return "Gemini ne répond pas. Vérifie ta connexion et réessaie." }
        if last.code == -1 { return "Réseau : \(last.body). Vérifie ta connexion (et coupe le VPN si besoin)." }
        if last.code == 0 { return "Gemini a renvoyé une réponse vide sur \(tried.count) modèles. Reformule ou réessaie." }
        return Self.readable(code: last.code, body: last.body) + " J'ai essayé \(tried.count) modèles (\(tried.joined(separator: ", "))). Réessaie dans une minute."
    }

    private func generate(system: String?, contents: [[String: Any]], json: Bool = false) async throws -> String {
        guard !apiKey.isEmpty else { throw GeminiError.noKey }
        inflight += 1
        defer { inflight -= 1 }
        let models = await candidates()
        var last: (code: Int, body: String)?
        for pass in 0..<2 {
            for model in models {
                var useThinking = true
                attempts: while true {
                    do {
                        let req = try makeRequest(model: model, stream: false, system: system, contents: contents, json: json, thinking: useThinking, maxTokens: 2000)
                        let (data, resp) = try await session.data(for: req)
                        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                        let body = String(data: data, encoding: .utf8) ?? ""
                        switch classify(code, body, useThinking: useThinking) {
                        case .ok:
                            let text = parseParts(data).text
                            if text.isEmpty { last = (0, ""); break attempts }
                            activeModel = model
                            return text
                        case .dropThinking:
                            useThinking = false
                            continue attempts
                        case .nextModel(let c, let b):
                            last = (c, b)
                            break attempts
                        case .fail(let c, let b):
                            throw GeminiError.bad(Self.readable(code: c, body: b))
                        }
                    } catch let e as URLError {
                        last = (-1, e.localizedDescription)
                        break attempts
                    }
                }
            }
            if pass == 0 { try? await Task.sleep(for: .seconds(2)) }
        }
        throw GeminiError.bad(failureMessage(last, tried: models))
    }

    /// Tour de chat en streaming SSE avec function calling : le texte arrive mot par mot via `onDelta`,
    /// les appels de fonctions sont collectés et renvoyés (jamais interprétés depuis le texte).
    func chatTurn(history: [ChatMessage], system: String, tools: [[String: Any]], onDelta: @escaping (String) -> Void) async throws -> ChatTurn {
        guard !apiKey.isEmpty else { throw GeminiError.noKey }
        inflight += 1
        defer { inflight -= 1 }
        let contents = chatContents(history)
        let models = await candidates()
        var last: (code: Int, body: String)?
        for pass in 0..<2 {
            for model in models {
                var useThinking = true
                attempts: while true {
                    do {
                        let req = try makeRequest(model: model, stream: true, system: system, contents: contents, json: false,
                                                  thinking: useThinking, maxTokens: 2048, tools: tools)
                        let (bytes, resp) = try await session.bytes(for: req)
                        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                        if code != 200 {
                            var body = ""
                            for try await l in bytes.lines { body += l; if body.count > 600 { break } }
                            switch classify(code, body, useThinking: useThinking) {
                            case .dropThinking:
                                useThinking = false
                                continue attempts
                            case .fail(let c, let b):
                                throw GeminiError.bad(Self.readable(code: c, body: b))
                            case .nextModel(let c, let b):
                                last = (c, b)
                                break attempts
                            case .ok:
                                break attempts
                            }
                        }
                        var text = ""
                        var calls: [ToolCall] = []
                        do {
                            for try await line in bytes.lines {
                                guard line.hasPrefix("data:") else { continue }
                                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                                let chunk = parseParts(Data(payload.utf8))
                                if !chunk.text.isEmpty { text += chunk.text; onDelta(chunk.text) }
                                calls += chunk.calls
                            }
                        } catch {
                            // Coupure en plein flux : on garde ce qui est déjà arrivé.
                            if !text.isEmpty || !calls.isEmpty { activeModel = model; return ChatTurn(text: text, calls: calls, model: model) }
                            throw error
                        }
                        if !text.isEmpty || !calls.isEmpty {
                            activeModel = model
                            return ChatTurn(text: text, calls: calls, model: model)
                        }
                        last = (0, "")
                        break attempts
                    } catch let e as URLError {
                        last = (-1, e.localizedDescription)
                        break attempts
                    }
                }
            }
            if pass == 0 { try? await Task.sleep(for: .seconds(2)) }
        }
        throw GeminiError.bad(failureMessage(last, tried: models))
    }

    // MARK: Voix naturelle (Gemini TTS) – renvoie un fichier WAV, ou nil si indisponible
    func synthesizeSpeech(_ text: String, voice: String = "Puck", style: String = "Dis ceci en français, avec un ton chaleureux et naturel") async -> Data? {
        guard !apiKey.isEmpty else { return nil }
        _ = await candidates()
        let model = ttsModel ?? "gemini-2.5-flash-preview-tts"
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else { return nil }
        let body: [String: Any] = [
            "contents": [["parts": [["text": "\(style) : \(text)"]]]],
            "generationConfig": ["responseModalities": ["AUDIO"],
                                 "speechConfig": ["voiceConfig": ["prebuiltVoiceConfig": ["voiceName": voice]]]] as [String: Any]
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"; req.timeoutInterval = 25
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = payload
        guard let (data, resp) = try? await session.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cands = root["candidates"] as? [[String: Any]],
              let content = cands.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let inline = parts.first?["inlineData"] as? [String: Any],
              let b64 = inline["data"] as? String,
              let pcm = Data(base64Encoded: b64) else { return nil }
        return Self.wav(fromPCM: pcm)
    }

    private static func wav(fromPCM pcm: Data, sampleRate: Int = 24000) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(Data("RIFF".utf8)); u32(UInt32(36 + pcm.count)); d.append(Data("WAVE".utf8))
        d.append(Data("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append(Data("data".utf8)); u32(UInt32(pcm.count)); d.append(pcm)
        return d
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
