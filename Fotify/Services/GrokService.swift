import Foundation
import UIKit

// MARK: - Response Model

struct GrokCommandResponse {
    enum Action {
        case showScreenshots
        case showDuplicates
        case showPhotos
        case tagPhotos
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

    func processCommand(_ command: String, photoLibrary: PhotoLibraryService) async -> GrokCommandResponse {
        let lower = command.lowercased()

        // Local matching first
        if lower.contains("captura") || lower.contains("screenshot") {
            return GrokCommandResponse(action: .showScreenshots, message: "Mostrando capturas")
        }
        if lower.contains("duplicado") || lower.contains("repetid") {
            return GrokCommandResponse(action: .showDuplicates, message: "Buscando duplicados")
        }
        if lower.contains("foto") || lower.contains("galería") || lower.contains("librería") {
            return GrokCommandResponse(action: .showPhotos, message: "Mostrando librería")
        }
        if lower.contains("tag") || lower.contains("etiquet") || lower.contains("clasific") {
            return GrokCommandResponse(action: .tagPhotos, message: "Clasificando fotos")
        }

        guard isConfigured else {
            return GrokCommandResponse(action: .none, message: "API key no configurada.")
        }

        return await sendChat(prompt: """
            Sos el asistente de Fotify, una app de gestión de fotos para iOS.
            El usuario tiene \(await photoLibrary.photoCount) fotos y \(await photoLibrary.screenshotCount) capturas.
            Respondé en español, breve (max 2 oraciones).
            Si el usuario pide una acción, respondé con JSON:
            {"action": "screenshots|duplicates|photos|tags", "message": "tu respuesta"}
            Si es solo pregunta:
            {"action": "none", "message": "tu respuesta"}
            Usuario: \(command)
        """)
    }

    // MARK: - Image Classification

    func classifyImage(_ image: UIImage) async -> [String] {
        guard isConfigured else { return [] }
        guard let imageData = image.jpegData(compressionQuality: 0.7) else { return [] }
        let base64 = imageData.base64EncodedString()

        let requestBody: [String: Any] = [
            "model": "llama-3.2-90b-vision-preview",
            "messages": [
                [
                    "role": "system",
                    "content": """
                        You are a photo classifier. Return ONLY a JSON array of tags in Spanish.
                        Categories: paisaje, retrato, selfie, comida, mascota, documento, meme,
                        captura_pantalla, naturaleza, ciudad, playa, montaña, familia, amigos, deporte,
                        arte, texto, recibo, noche, atardecer, interior, exterior, vehiculo, celebracion.
                        Return 3-7 tags. Example: ["paisaje", "naturaleza", "montaña"]
                    """
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image_url",
                            "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
                        ],
                        [
                            "type": "text",
                            "text": "Classify this photo with tags."
                        ]
                    ]
                ]
            ],
            "max_tokens": 200,
            "temperature": 0.3
        ]

        return await sendImageRequest(requestBody) ?? []
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

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                return parseCommandResponse(content)
            }
        } catch {
            return GrokCommandResponse(action: .none, message: "Error: \(error.localizedDescription)")
        }

        return GrokCommandResponse(action: .none, message: "Sin respuesta")
    }

    private func sendImageRequest(_ body: [String: Any]) async -> [String]? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                return parseTags(from: content)
            }
        } catch {
            print("Groq API error: \(error)")
        }
        return nil
    }

    // MARK: - Parsing

    private func parseCommandResponse(_ content: String) -> GrokCommandResponse {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let actionStr = json["action"],
           let message = json["message"] {
            let action: GrokCommandResponse.Action = switch actionStr {
            case "screenshots": .showScreenshots
            case "duplicates": .showDuplicates
            case "photos": .showPhotos
            case "tags": .tagPhotos
            default: .none
            }
            return GrokCommandResponse(action: action, message: message)
        }

        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}") {
            let jsonString = String(trimmed[start...end])
            if let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               let message = json["message"] {
                let actionStr = json["action"] ?? "none"
                let action: GrokCommandResponse.Action = switch actionStr {
                case "screenshots": .showScreenshots
                case "duplicates": .showDuplicates
                case "photos": .showPhotos
                case "tags": .tagPhotos
                default: .none
                }
                return GrokCommandResponse(action: action, message: message)
            }
        }

        return GrokCommandResponse(action: .chat(trimmed), message: trimmed)
    }

    private func parseTags(from content: String) -> [String] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = trimmed.data(using: .utf8),
           let tags = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return tags
        }

        if let start = trimmed.firstIndex(of: "["),
           let end = trimmed.lastIndex(of: "]") {
            let jsonString = String(trimmed[start...end])
            if let data = jsonString.data(using: .utf8),
               let tags = try? JSONSerialization.jsonObject(with: data) as? [String] {
                return tags
            }
        }

        return []
    }
}
