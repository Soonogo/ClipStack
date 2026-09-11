import AppKit
import Combine
import ImageIO

/// Owns the persisted clipboard history and the on-disk image cache.
/// All mutations happen on the main thread (the monitor polls on the
/// main run loop); disk writes are atomic and debounced.
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    @Published var maxHistory: Int {
        didSet {
            UserDefaults.standard.set(maxHistory, forKey: "maxHistory")
            enforceLimit()
            scheduleSave()
        }
    }

    let baseDirectory: URL
    let imagesDirectory: URL
    private let historyURL: URL

    /// Bounded thumbnail cache: never holds more than `countLimit` small images,
    /// so memory stays flat regardless of history size.
    private let thumbnailCache = NSCache<NSString, NSImage>()

    private var saveTask: Task<Void, Never>?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseDirectory = appSupport.appendingPathComponent("ClipStack", isDirectory: true)
        imagesDirectory = baseDirectory.appendingPathComponent("Images", isDirectory: true)
        historyURL = baseDirectory.appendingPathComponent("history.json")
        maxHistory = UserDefaults.standard.object(forKey: "maxHistory") as? Int ?? 500
        thumbnailCache.countLimit = 150

        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Mutations

    func add(_ item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
            var existing = items.remove(at: index)
            existing.createdAt = Date()
            items.insert(existing, at: 0)
        } else {
            items.insert(item, at: 0)
        }
        enforceLimit()
        scheduleSave()
    }

    /// Move an existing item to the top without touching its hash —
    /// used when the user re-pastes an entry.
    func moveToTop(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }), index != 0 else { return }
        let existing = items.remove(at: index)
        items.insert(existing, at: 0)
        scheduleSave()
    }

    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        scheduleSave()
    }

    func delete(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        removeImageIfNeeded(items[index])
        items.remove(at: index)
        scheduleSave()
    }

    func clear(keepPinned: Bool = true) {
        let removed = keepPinned ? items.filter { !$0.isPinned } : items
        for item in removed { removeImageIfNeeded(item) }
        items = keepPinned ? items.filter { $0.isPinned } : []
        scheduleSave()
    }

    // MARK: - Images

    @discardableResult
    func saveImage(data: Data) -> String? {
        let fileName = UUID().uuidString + ".png"
        let url = imagesDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    func imageURL(fileName: String) -> URL {
        imagesDirectory.appendingPathComponent(fileName)
    }

    /// Downsampled thumbnail via ImageIO — decodes at the target pixel size,
    /// so a 4K screenshot costs only a few KB of memory.
    func thumbnail(fileName: String, maxPixel: Int = 160) -> NSImage? {
        let key = fileName as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        let url = imagesDirectory.appendingPathComponent(fileName) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        thumbnailCache.setObject(image, forKey: key)
        return image
    }

    func fullImage(fileName: String) -> NSImage? {
        NSImage(contentsOf: imagesDirectory.appendingPathComponent(fileName))
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data)
        else { return }
        // Drop items whose payload vanished from disk.
        items = decoded.filter { item in
            guard let name = item.imageFileName else { return true }
            return FileManager.default.fileExists(atPath: imagesDirectory.appendingPathComponent(name).path)
        }
        items.sort { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.createdAt > b.createdAt
        }
        enforceLimit()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.saveNow()
        }
    }

    func saveNow() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: historyURL, options: .atomic)
        } catch {
            NSLog("ClipStack: failed to persist history: \(error.localizedDescription)")
        }
    }

    private func enforceLimit() {
        var unpinnedCount = items.count - items.filter(\.isPinned).count
        guard unpinnedCount > maxHistory else { return }
        var index = items.count - 1
        while index >= 0, unpinnedCount > maxHistory {
            let item = items[index]
            if !item.isPinned {
                removeImageIfNeeded(item)
                items.remove(at: index)
                unpinnedCount -= 1
            }
            index -= 1
        }
    }

    private func removeImageIfNeeded(_ item: ClipboardItem) {
        guard let name = item.imageFileName else { return }
        thumbnailCache.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(name))
    }
}
