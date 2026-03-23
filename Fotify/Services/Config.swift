import Foundation

enum Config {
    // MARK: - API Keys (Groq)
    static let groqAPIKey: String = "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"
    static let groqModel: String = "llama-3.3-70b-versatile"
    static let groqVisionModel: String = "meta-llama/llama-4-scout-17b-16e-instruct"

    // MARK: - Limits
    static let quickScanLimit: Int = 10  // DEBUG: solo 10 fotos para testing
    static let debugMode: Bool = true
    static let maxPhotosForGroqScan: Int = 100
    static let thumbnailSize: CGFloat = 200
    static let groqImageSize: CGFloat = 512
    static let hashImageWidth: Int = 9
    static let hashImageHeight: Int = 8

    // MARK: - Duplicate Detection
    static let duplicateHashThreshold: Int = 5
}
