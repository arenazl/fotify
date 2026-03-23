import Foundation

// MARK: - Response Model

struct GrokCommandResponse {
    enum Action {
        case showScreenshots
        case showDuplicates
        case showPhotos
        case tagPhotos
        case searchByFilters([SearchFilter])
        case searchByLocation(String)
        case createAlbum(String, [SearchFilter])
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

        // Send to Groq — structured search
        let prompt = """
        Sos el motor de búsqueda de Fotify. Las fotos están indexadas con campos: personas, lugar, objetos, escena, actividad, texto.
        El usuario es de ARGENTINA. Priorizá ubicaciones argentinas.

        El usuario dice: "\(command)"

        Respondé SOLO con este JSON (sin markdown, sin ```):
        {"action": "search", "filters": [{"field": "campo", "values": ["valor1", "valor2"]}], "message": "respuesta"}

        Reglas de filters:
        - field: personas, lugar, objetos, escena, actividad, texto
        - Si busca personas, usá field "personas" con values ["not_empty"]
        - values es un ARRAY con la palabra + sinónimos + variantes sin tildes + gerundios + plurales
          Ejemplo: noche → values: ["noche", "nocturno", "oscuro", "nocturna"]
          Ejemplo: montaña → values: ["montaña", "montana", "monte", "sierra", "cerro"]
          Ejemplo: jugar → values: ["jugando", "juego", "jugar"]
          Ejemplo: niños → values: ["niño", "nino", "niña", "nina", "chico", "nene"]
        - Priorizá: escena > objetos > lugar > actividad
        - Para búsquedas simples, usá UN solo filtro
          "comida" → UN filtro en objetos: ["comida", "plato", "platos", "alimento"]
          "capturas" → UN filtro en escena: ["captura", "screenshot", "pantalla"]

        Reglas de action:
        - "search": buscar en los campos indexados (lo más común)
        - "location": si busca por ciudad/lugar/país. En filters poné [{"field":"lugar","values":["nombre completo con provincia y Argentina"]}]
          "fotos en Padua" → action "location", filters: [{"field":"lugar","values":["Padua, Buenos Aires, Argentina"]}]
        - "create_album": si pide crear carpeta/álbum. Mismo formato de filters.
        - "screenshots": si pide capturas de pantalla
        - "duplicates": si pide duplicados
        - "chat": si es pregunta general
        """

        await DebugLogger.shared.log("GROQ", "Query: \"\(command)\"")
        await DebugLogger.shared.log("GROQ", "Prompt enviado a Groq...")

        let response = await sendChat(prompt: prompt)

        switch response.action {
        case .searchByFilters(let filters):
            await DebugLogger.shared.log("GROQ", "Action: search, filters: \(filters.map { "\($0.field):\($0.values.prefix(3))" })")
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

    // MARK: - Filter Parsing

    private func parseFilters(from json: [String: Any]) -> [SearchFilter] {
        guard let filtersArray = json["filters"] as? [[String: Any]] else {
            // Fallback: try old "tags" format
            if let tags = json["tags"] as? [String] {
                return tags.map { SearchFilter(field: "escena", values: [$0]) }
            }
            return []
        }

        return filtersArray.compactMap { filterDict in
            guard let field = filterDict["field"] as? String,
                  let values = filterDict["values"] as? [String] else { return nil }
            return SearchFilter(field: field, values: values)
        }
    }

    // MARK: - Parsing

    private func parseCommandResponse(_ content: String) -> GrokCommandResponse {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find JSON in response
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

        // Parse filters array
        let filters = parseFilters(from: json)

        switch actionStr {
        case "search":
            return GrokCommandResponse(action: .searchByFilters(filters), message: message)
        case "location":
            let place = filters.first?.values.first ?? ""
            return GrokCommandResponse(action: .searchByLocation(place), message: message)
        case "create_album":
            return GrokCommandResponse(action: .createAlbum(message, filters), message: message)
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
