import Foundation

// MARK: - Response Model

struct GrokCommandResponse {
    enum Action {
        case showScreenshots
        case showDuplicates
        case showPhotos
        case tagPhotos
        case searchByTerms([String])
        case searchByLocation(String)
        case createAlbum(String, [String])
        case chat(String)
        case none
    }

    let action: Action
    let message: String
}

// MARK: - Groq Service (LLama 3.3 via Groq API)

actor GrokService {
    static let shared = GrokService()

    private let baseURL = "https://api.groq.com/openai/v1/chat/completions"
    private var apiKey: String { Config.groqAPIKey }
    private var model: String { Config.groqModel }

    var isConfigured: Bool { !apiKey.isEmpty }

    // MARK: - Command Processing

    func processCommand(_ command: String, photoLibrary: PhotoLibraryService, availableTags: [String]) async -> GrokCommandResponse {
        // Local matching first
        let lower = command.lowercased()

        if lower.contains("captura") || lower.contains("screenshot") {
            return GrokCommandResponse(action: .showScreenshots, message: "Mostrando capturas")
        }
        if lower.contains("duplicado") || lower.contains("repetid") {
            return GrokCommandResponse(action: .showDuplicates, message: "Buscando duplicados")
        }

        guard isConfigured else {
            return GrokCommandResponse(action: .none, message: "API key no configurada.")
        }

        // Send to Groq — search with synonyms
        let prompt = """
        El usuario busca fotos con: "\(command)"
        El usuario es de ARGENTINA. Priorizá ubicaciones argentinas.

        Extraé el concepto principal ignorando "fotos de/con/en", "mostrame", etc.
        Determiná qué tipo de acción es y respondé con JSON (sin markdown, sin ```):

        Si busca por contenido → {"action": "search", "search": ["palabra1", "sinónimo1", "sinónimo2", ...], "message": "respuesta"}
        Si busca por ciudad/lugar/país → {"action": "location", "place": "Lugar, Provincia, Argentina", "message": "respuesta"}
        Si pide crear carpeta/álbum → {"action": "create_album", "search": ["palabras clave"], "album": "nombre", "message": "respuesta"}
        Si pide capturas → {"action": "screenshots", "message": "respuesta"}
        Si pide duplicados → {"action": "duplicates", "message": "respuesta"}
        Si es pregunta general → {"action": "chat", "message": "respuesta"}

        Para action "search": generá las palabras clave incluyendo sinónimos, variantes sin tildes, regionalismos y algún error de ortografía común. SIEMPRE al menos 5 palabras.
        """

        await DebugLogger.shared.log("GROQ", "Query: \"\(command)\"")
        await DebugLogger.shared.log("GROQ", "Prompt enviado a Groq...")

        let response = await sendChat(prompt: prompt)

        switch response.action {
        case .searchByTerms(let terms):
            await DebugLogger.shared.log("GROQ", "Action: search, terms: \(terms.prefix(5))")
        case .searchByLocation(let place):
            await DebugLogger.shared.log("GROQ", "Action: location, lugar: \(place)")
        case .createAlbum(let name, let tags):
            await DebugLogger.shared.log("GROQ", "Action: create_album, nombre: \(name), tags: \(tags)")
        case .showScreenshots:
            await DebugLogger.shared.log("GROQ", "Action: screenshots")
        case .showDuplicates:
            await DebugLogger.shared.log("GROQ", "Action: duplicates")
        case .chat(let msg):
            await DebugLogger.shared.log("GROQ", "Action: chat, msg: \(msg)")
        default:
            await DebugLogger.shared.log("GROQ", "Action: \(response.message)")
        }

        return response
    }

    // MARK: - HTTP

    private func sendChat(prompt: String) async -> GrokCommandResponse {
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 300,
            "temperature": 0.3
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            return GrokCommandResponse(action: .none, message: "Error interno")
        }

        guard let url = URL(string: baseURL) else {
            return GrokCommandResponse(action: .none, message: "Error interno")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        request.timeoutInterval = 15

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                return parseCommandResponse(content)
            }
        } catch {
            return GrokCommandResponse(action: .chat("Error: \(error.localizedDescription)"), message: "Error de conexión")
        }

        return GrokCommandResponse(action: .none, message: "Sin respuesta")
    }

    // MARK: - Parsing

    private func parseCommandResponse(_ content: String) -> GrokCommandResponse {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        var jsonString = trimmed
        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}") {
            jsonString = String(trimmed[start...end])
        }

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let actionStr = json["action"] as? String,
              let message = json["message"] as? String else {
            return GrokCommandResponse(action: .chat(trimmed), message: trimmed)
        }

        let searchTerms = json["search"] as? [String] ?? json["tags"] as? [String] ?? []

        switch actionStr {
        case "search":
            return GrokCommandResponse(action: .searchByTerms(searchTerms), message: message)
        case "location":
            let place = json["place"] as? String ?? searchTerms.first ?? ""
            return GrokCommandResponse(action: .searchByLocation(place), message: message)
        case "create_album":
            return GrokCommandResponse(action: .createAlbum(json["album"] as? String ?? message, searchTerms), message: message)
        case "screenshots":
            return GrokCommandResponse(action: .showScreenshots, message: message)
        case "duplicates":
            return GrokCommandResponse(action: .showDuplicates, message: message)
        case "chat":
            return GrokCommandResponse(action: .chat(message), message: message)
        default:
            return GrokCommandResponse(action: .chat(message), message: message)
        }
    }
}
