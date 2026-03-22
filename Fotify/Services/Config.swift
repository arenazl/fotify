import Foundation

enum Config {
    // MARK: - API Keys
    // Set your Grok API key here or via environment variable GROK_API_KEY
    static let grokAPIKey: String = ""

    // MARK: - Limits
    static let maxPhotosForVisionScan: Int = 500
    static let maxPhotosForGrokScan: Int = 100
    static let thumbnailSize: CGFloat = 200
    static let grokImageSize: CGFloat = 512
    static let hashImageWidth: Int = 9
    static let hashImageHeight: Int = 8

    // MARK: - Duplicate Detection
    static let duplicateHashThreshold: Int = 5  // Hamming distance
}
