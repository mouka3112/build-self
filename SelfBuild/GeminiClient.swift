import Foundation
import Combine
import UIKit

struct HomeworkCheck: Decodable { let valid: Bool; let validatedIndices: [Int]; let comment: String }
struct ReceiptResult: Decodable { let amount: Double; let category: String; let note: String }
struct Reminder: Decodable { let minute: Int; let title: String; let body: String }

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

    // MARK: Modèles de secours (si Google renvoie 503 « forte demande » / 429 / 404)
    private struct ModelList: Decodable {
        struct M: Decodable { let name: String; let supportedGenerationMethods: [String]? }
        let models: [M]
    }
    private var cachedModels: [String] = []
    private var cachedFor = ""
    private var ttsModel: String?

    private func candidates() async -> [String] {
        if cachedFor == modelName, !cachedModels.isEmpty { return cachedModels }
        var list = [modelName]
        if let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200&key=\(apiKey)"),
           let (data, _) = try? await session.data(from: url),
           let r = try? JSONDecoder().decode(ModelList.self, from: data) {
            let names = r.models.filter { ($0.supportedGenerationMethods ?? []).contains("generateContent") }
                .map { $0.name.replacingOccurrences(of: "models/", with: "") }
            ttsModel = names.first { $0.contains("tts") && $0.contains("flash") } ?? names.first { $0.contains("tts") }
            let bad = ["image", "tts", "audio", "live", "embedding", "robotics", "computer", "vision", "imagen", "veo", "learnlm", "gemma", "aqa", "native"]
            let flash = names.filter { n in n.contains("flash") && !bad.contains { n.contains($0) } }
            let lite = flash.filter { $0.contains("lite") }.sorted(by: >)
            let rest = flash.filter { !$0.contains("lite") }.sorted(by: >)
            for m in lite + rest where !list.contains(m) { list.append(m) }
        }
        for alias in ["gemini-flash-latest", "gemini-flash-lite-latest"] where !list.contains(alias) { list.append(alias) }
        cachedModels = Array(list.prefix(5)); cachedFor = modelName
        return cachedModels
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

    func chat(history: [ChatMessage], store: AppStore) async throws -> String {
        try await generate(system: systemPrompt(store), contents: chatContents(history))
    }

    /// Texte libre (avec photo optionnelle).
    func text(_ prompt: String, image: UIImage? = nil, store: AppStore? = nil) async throws -> String {
        var parts: [[String: Any]] = [["text": prompt]]
        if let b64 = image?.jpegBase64() { parts.append(["inline_data": ["mime_type": "image/jpeg", "data": b64]]) }
        return try await generate(system: store.map { systemPrompt($0) }, contents: [["role": "user", "parts": parts]])
    }

    /// Texte avec plusieurs photos (cours).
    func text(_ prompt: String, images: [UIImage], store: AppStore? = nil) async throws -> String {
        var parts: [[String: Any]] = [["text": prompt]]
        for img in images.prefix(4) { if let b64 = img.jpegBase64() { parts.append(["inline_data": ["mime_type": "image/jpeg", "data": b64]]) } }
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
        return try await json(HomeworkCheck.self, prompt, image: image)
    }

    func scanReceipt(image: UIImage) async throws -> ReceiptResult {
        let cats = Finance.categories.map(\.name).joined(separator: ", ")
        let prompt = """
        Analyse ce ticket de caisse (Tunisie, montants en dinars tunisiens DT, souvent 3 décimales). Réponds UNIQUEMENT en JSON :
        {"amount": total TTC en nombre, "category": une valeur parmi [\(cats)], "note": "nom du magasin ou résumé court"}
        """
        var r = try await json(ReceiptResult.self, prompt, image: image)
        if !Finance.categories.map(\.name).contains(r.category) { r = ReceiptResult(amount: r.amount, category: "Autre", note: r.note) }
        return r
    }

    func proactiveReminders(store: AppStore) async throws -> [Reminder] {
        let prompt = """
        Génère 3 à 5 rappels de notification pour le reste de la journée de Melik (discipline, devoirs, nutrition, sommeil), tous APRÈS \(timeString(store.minutesNow + 5)).
        Inclus au moins un rappel d'hygiène (dents, visage, cheveux ou douche) si ce n'est pas déjà fait.
        Réponds UNIQUEMENT en JSON : [{"minute": minutes depuis minuit (entier), "title": "max 5 mots", "body": "max 15 mots, direct, motivant"}]
        """
        return try await json([Reminder].self, prompt, store: store)
    }

    // MARK: Contexte donné à Nexus
    private func systemPrompt(_ s: AppStore) -> String {
        let df = DateFormatter(); df.locale = Locale(identifier: "fr_FR"); df.dateFormat = "EEEE d MMMM yyyy, HH:mm"
        let iso = DateFormatter(); iso.locale = Locale(identifier: "en_US_POSIX"); iso.dateFormat = "yyyy-MM-dd HH:mm"
        return """
        Tu es Nexus, le coach de vie intégré à SELF BUILD, l'app de Melik (15 ans, 1m83, 9ème année au collège pilote du Kef, Tunisie).
        Objectifs de Melik : discipline de fer (études + musculation), nutrition optimisée, gestion de l'argent de poche, autonomie.
        Style : français, tutoiement, direct, motivant, concis (max ~120 mots sauf si on te demande plus). Conseils adaptés à un adolescent :
        pas de régime extrême, pas de produits dopants, sommeil 8-9 h, technique avant charges.
        Maintenant : \(df.string(from: .now)) (format machine : \(iso.string(from: .now))).

        TOUTES LES DONNÉES DE MELIK DANS L'APP (tu y as accès, appuie-toi dessus et ne dis jamais que tu n'y as pas accès) :
        \(s.nexusContext())
        (Son journal Safe Space et ses photos de progression ne te sont volontairement jamais transmis.)

        ACTIONS : tout ce que Melik dit avoir FAIT, ou te demande d'enregistrer, doit être inscrit dans l'app en ajoutant à la FIN de ta réponse un tag par action, au format exact [[ACT:{json}]] (JSON valide sur UNE ligne). Sans tag, RIEN n'est enregistré. Types :
        {"type":"expense","amount":3,"category":"Snacks|Nutrition|Transport|École|Études|Sport|Loisirs|Autre","note":"..."}
        {"type":"income","amount":10,"note":"..."}
        {"type":"meal","items":[{"name":"...","grams":150,"kcal":250,"protein":30}]}   (estime les TOTAUX de ce qu'il a mangé)
        {"type":"water","ml":500}
        {"type":"hygiene","habit":"teethAM|faceAM|teethPM|facePM|shower|hair"}
        {"type":"task_done","title":"mot-clé de la tâche du planning"}
        {"type":"start_task","title":"mot-clé"}   (il la commence maintenant)
        {"type":"add_task","title":"...","start":"HH:mm","duration":30,"kind":"study|workout|meal|hygiene|rest|other"}   (ajoute une tâche au Hub)
        {"type":"remove_task","title":"mot-clé"}
        {"type":"switch","title":"activité","minutes":30}
        {"type":"replan","tasks":[{"title":"mot-clé d'une tâche restante","start":"HH:mm","duration":45}]}   (réorganise les tâches restantes à partir de maintenant, sans chevauchement, sans toucher aux cours ni au sommeil)
        {"type":"workout_set","exercise":"Squat","weight":60,"reps":8}
        {"type":"health","kind":"Sommeil|Symptôme|Médicament|Énergie|Autre","text":"..."}
        {"type":"note","text":"..."}
        {"type":"reminder","title":"...","date":"yyyy-MM-dd HH:mm","repeat":"none|daily|weekly|monthly"}   (calcule la date à partir de maintenant)
        {"type":"exam","subject":"Maths","date":"yyyy-MM-dd","topic":"..."}
        {"type":"homework","subject":"Maths","topic":"exercices p.45","date":"yyyy-MM-dd"}
        {"type":"tutor_session","title":"nom du prof ou matière"}   (séance de cours particulier faite)
        {"type":"challenge_done","title":"mot-clé du défi"}
        {"type":"undo","what":"expense|meal"}   (annule la dernière saisie si Melik s'est trompé)
        Exemples :
        « j'ai dépensé 3 dinars en snack » → « Noté, 3 TND de snacks. [[ACT:{"type":"expense","amount":3,"category":"Snacks","note":"snack"}]] »
        « je viens de manger du riz et 150 g de poulet » → « Super apport en protéines ! [[ACT:{"type":"meal","items":[{"name":"Riz blanc","grams":200,"kcal":260,"protein":5},{"name":"Escalope de poulet","grams":150,"kcal":248,"protein":46}]}]] »
        « j'ai fini mes devoirs » → « Bien joué ! [[ACT:{"type":"task_done","title":"devoirs"}]] »
        « je me suis brossé les dents et lavé le visage ce soir » → [[ACT:{"type":"hygiene","habit":"teethPM"}]] [[ACT:{"type":"hygiene","habit":"facePM"}]]
        « j'ai fait 8 reps à 60 kg au squat » → [[ACT:{"type":"workout_set","exercise":"Squat","weight":60,"reps":8}]]
        N'enregistre que ce qu'il affirme avoir fait ou demande explicitement (jamais une intention vague ni une question). Confirme en une phrase.
        Si utile, termine aussi par UN tag [[GOTO:x]] (x parmi : muscu, nutrition, study, hygiene, wardrobe, kitchen, music, running, projects, challenges, capsule, reports, health, safe, finance, notes, reminders, lessons, school, tutors) pour ouvrir le bon module.
        """
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

    // MARK: Réseau (streaming + modèles de secours)
    /// Gemini 3 réfléchit à fond par défaut (lent) : on demande un raisonnement léger.
    private func thinkingConfig(_ model: String) -> [String: Any]? {
        let m = model.lowercased()
        if m.contains("gemini-3") { return ["thinkingLevel": "low"] }
        if m.contains("2.5") && m.contains("flash") { return ["thinkingBudget": 0] }
        return nil
    }

    private func makeRequest(model: String, stream: Bool, system: String?, contents: [[String: Any]], json: Bool, thinking: Bool, maxTokens: Int) throws -> URLRequest {
        let method = stream ? "streamGenerateContent" : "generateContent"
        var comps = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):\(method)")!
        var items = [URLQueryItem(name: "key", value: apiKey)]
        if stream { items.append(URLQueryItem(name: "alt", value: "sse")) }
        comps.queryItems = items
        var gen: [String: Any] = ["maxOutputTokens": maxTokens]
        if json { gen["responseMimeType"] = "application/json" }
        if thinking, let t = thinkingConfig(model) { gen["thinkingConfig"] = t }
        var body: [String: Any] = ["contents": contents, "generationConfig": gen]
        if let system { body["systemInstruction"] = ["parts": [["text": system]]] }
        var req = URLRequest(url: comps.url!)
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

    private func generate(system: String?, contents: [[String: Any]], json: Bool = false) async throws -> String {
        guard !apiKey.isEmpty else { throw GeminiError.noKey }
        inflight += 1
        defer { inflight -= 1 }
        let models = await candidates()
        var lastMessage = "Aucun modèle disponible."
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
                            let r = try JSONDecoder().decode(GenResponse.self, from: data)
                            let text = r.candidates?.first?.content?.parts?.compactMap(\.text).joined() ?? ""
                            if text.isEmpty { lastMessage = "Réponse vide de Gemini."; break attempts }
                            activeModel = model
                            return text
                        case .dropThinking:
                            useThinking = false
                            continue attempts
                        case .nextModel(let c, let b):
                            lastMessage = "Erreur Gemini \(c) : \(b.prefix(160))"
                            break attempts
                        case .fail(let c, let b):
                            throw GeminiError.bad("Erreur Gemini \(c) : \(b.prefix(180))")
                        }
                    } catch let e as URLError {
                        lastMessage = "Réseau : \(e.localizedDescription)"
                        break attempts
                    }
                }
            }
            if pass == 0 { try? await Task.sleep(for: .seconds(2)) }
        }
        throw GeminiError.bad(lastMessage)
    }

    /// Chat en streaming : le texte arrive mot par mot via `onDelta`.
    func streamChat(history: [ChatMessage], store: AppStore, onDelta: @escaping (String) -> Void) async throws {
        guard !apiKey.isEmpty else { throw GeminiError.noKey }
        inflight += 1
        defer { inflight -= 1 }
        let contents = chatContents(history)
        let system = systemPrompt(store)
        let models = await candidates()
        var lastMessage = "Aucun modèle disponible."
        for pass in 0..<2 {
            for model in models {
                var useThinking = true
                attempts: while true {
                    do {
                        let req = try makeRequest(model: model, stream: true, system: system, contents: contents, json: false, thinking: useThinking, maxTokens: 1800)
                        let (bytes, resp) = try await session.bytes(for: req)
                        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                        if code != 200 {
                            var body = ""
                            for try await l in bytes.lines { body += l; if body.count > 400 { break } }
                            switch classify(code, body, useThinking: useThinking) {
                            case .dropThinking:
                                useThinking = false
                                continue attempts
                            case .fail(let c, let b):
                                throw GeminiError.bad("Erreur Gemini \(c) : \(b.prefix(180))")
                            case .nextModel(let c, let b):
                                lastMessage = "Erreur Gemini \(c) : \(b.prefix(160))"
                                break attempts
                            case .ok:
                                break attempts
                            }
                        }
                        var got = false
                        do {
                            for try await line in bytes.lines {
                                guard line.hasPrefix("data:") else { continue }
                                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                                guard let d = payload.data(using: .utf8), let r = try? JSONDecoder().decode(GenResponse.self, from: d) else { continue }
                                let t = r.candidates?.first?.content?.parts?.compactMap(\.text).joined() ?? ""
                                if !t.isEmpty { got = true; onDelta(t) }
                            }
                        } catch {
                            if got { activeModel = model; return }
                            throw error
                        }
                        if got { activeModel = model; return }
                        lastMessage = "Réponse vide de Gemini."
                        break attempts
                    } catch let e as URLError {
                        lastMessage = "Réseau : \(e.localizedDescription)"
                        break attempts
                    }
                }
            }
            if pass == 0 { try? await Task.sleep(for: .seconds(2)) }
        }
        throw GeminiError.bad(lastMessage)
    }

    // MARK: Voix naturelle (Gemini TTS) – renvoie un fichier WAV, ou nil si indisponible
    private struct TTSResponse: Decodable {
        struct Cand: Decodable {
            struct Content: Decodable {
                struct Part: Decodable { struct Inline: Decodable { let data: String }; let inlineData: Inline? }
                let parts: [Part]?
            }
            let content: Content?
        }
        let candidates: [Cand]?
    }

    func synthesizeSpeech(_ text: String, voice: String = "Puck") async -> Data? {
        guard !apiKey.isEmpty else { return nil }
        _ = await candidates()
        let model = ttsModel ?? "gemini-2.5-flash-preview-tts"
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else { return nil }
        let body: [String: Any] = [
            "contents": [["parts": [["text": "Dis ceci en français, avec l'énergie d'un coach sportif : \(text)"]]]],
            "generationConfig": ["responseModalities": ["AUDIO"],
                                 "speechConfig": ["voiceConfig": ["prebuiltVoiceConfig": ["voiceName": voice]]]]
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"; req.timeoutInterval = 25
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = payload
        guard let (data, resp) = try? await session.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let r = try? JSONDecoder().decode(TTSResponse.self, from: data),
              let b64 = r.candidates?.first?.content?.parts?.first?.inlineData?.data,
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
