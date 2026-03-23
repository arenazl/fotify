import Foundation

// MARK: - Response Model

struct GrokCommandResponse {
    enum Action {
        case showScreenshots
        case showDuplicates
        case showPhotos
        case tagPhotos
        case searchByTags([String])
        case searchByLocation(String) // place name
        case createAlbum(String, [String]) // album name, search tags
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

        // Send to Groq — extract search keywords from user command
        let prompt = """
        Sos el asistente de Fotify, una app de fotos para iOS.
        El usuario tiene \(await photoLibrary.photoCount) fotos indexadas con descripciones en español.

        El usuario dice: "\(command)"

        Respondé SOLO con este JSON (sin markdown, sin ```):
        {"action": "search", "tags": ["palabra1", "palabra2"], "message": "tu respuesta corta en español"}

        Extraé las palabras clave en español para buscar en las descripciones de fotos.
        Por ejemplo: "fotos de mendoza con roberto" → tags: ["mendoza", "roberto"]
        "mi perro en la playa" → tags: ["perro", "playa"]
        "comida japonesa" → tags: ["comida", "japonesa", "sushi"]

        Si pide crear una carpeta/álbum, usá action "create_album" y en tags poné las palabras de búsqueda.
        Si busca por ubicación/lugar/ciudad/país, usá action "location" y en tags poné el nombre del lugar.
        Ejemplo: "fotos en Mendoza" → {"action": "location", "tags": ["Mendoza, Argentina"], "message": "Buscando fotos en Mendoza"}
        Si pide ver capturas, usá action "screenshots".
        Si pide duplicados, usá action "duplicates".
        Si es una pregunta general, usá action "chat".
        """

        let response = await sendChat(prompt: prompt)

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

        switch actionStr {
        case "search":
            let tags = json["tags"] as? [String] ?? []
            return GrokCommandResponse(action: .searchByTags(tags), message: message)
        case "classify":
            return GrokCommandResponse(action: .tagPhotos, message: message)
        case "location":
            let tags = json["tags"] as? [String] ?? []
            let place = tags.first ?? ""
            return GrokCommandResponse(action: .searchByLocation(place), message: message)
        case "create_album":
            let tags = json["tags"] as? [String] ?? []
            let albumName = json["album_name"] as? String ?? message
            return GrokCommandResponse(action: .createAlbum(albumName, tags), message: message)
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
