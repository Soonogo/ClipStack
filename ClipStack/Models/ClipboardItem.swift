import Foundation
import CryptoKit

enum ClipboardItemKind: String, Codable, CaseIterable {
    case text
    case link
    case image
    case file
}

struct ClipboardItem: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var kind: ClipboardItemKind
    /// Plain-text payload for `.text`/`.link`; display path for `.file`.
    var text: String?
    /// File name inside the images directory for `.image` items.
    var imageFileName: String?
    /// Absolute paths for `.file` items.
    var filePaths: [String]?
    var sourceAppName: String?
    var createdAt: Date = Date()
    var isPinned: Bool = false
    /// Stable dedupe key (SHA-256 of the primary payload).
    var contentHash: String

    var previewText: String {
        switch kind {
        case .text, .link:
            return text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        case .image:
            return "Image"
        case .file:
            let paths = filePaths ?? []
            if paths.count == 1, let last = paths.first?.components(separatedBy: "/").last {
                return last
            }
            return "\(paths.count) files"
        }
    }

    static func hash(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func hash(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
