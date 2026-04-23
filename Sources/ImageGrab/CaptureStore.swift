import AppKit
import Foundation
import ImageIO

// Thread-safe thumbnail cache
private final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    func object(forKey key: NSString) -> NSImage? {
        cache.object(forKey: key)
    }

    func setObject(_ image: NSImage, forKey key: NSString) {
        cache.setObject(image, forKey: key)
    }

    func removeObject(forKey key: NSString) {
        cache.removeObject(forKey: key)
    }
}

public struct CaptureEntry: Codable, Identifiable, Sendable {
    public let id: UUID
    public var filename: String
    public let originalFilename: String
    public let capturedAt: Date
}

@MainActor
public final class CaptureStore {
    public private(set) var entries: [CaptureEntry] = []
    private let fileManager: FileManager
    private let capturesDir: URL
    private let metadataURL: URL

    public init(capturesDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let base = capturesDirectory ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("repos/ImageGrab/captures")
        capturesDir = base
        metadataURL = base.appendingPathComponent(".metadata.json")
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        load()
    }

    public func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([CaptureEntry].self, from: data) else { return }
        // Only keep entries whose files still exist
        entries = decoded.filter { fileManager.fileExists(atPath: capturesDir.appendingPathComponent($0.filename).path) }
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: metadataURL)
    }

    @discardableResult
    public func addCapture(image: NSImage) -> CaptureEntry? {
        let timestamp = Self.timestampFormatter.string(from: Date())
        let filename = "capture-\(timestamp).webp"
        let url = capturesDir.appendingPathComponent(filename)

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        // Try WebP via CGImageDestination (available macOS 14+), fall back to PNG
        let webpTypeID = "org.webmproject.webp" as CFString
        let webpData = NSMutableData()
        var wrote = false
        if let dest = CGImageDestinationCreateWithData(webpData, webpTypeID, 1, nil) {
            CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            wrote = CGImageDestinationFinalize(dest)
        }

        if wrote {
            do {
                try (webpData as Data).write(to: url)
            } catch { return nil }
        } else {
            // Fallback to PNG if WebP encoding unavailable
            let pngFilename = "capture-\(timestamp).png"
            let pngURL = capturesDir.appendingPathComponent(pngFilename)
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }
            do {
                try pngData.write(to: pngURL)
            } catch { return nil }
            let entry = CaptureEntry(id: UUID(), filename: pngFilename, originalFilename: pngFilename, capturedAt: Date())
            entries.insert(entry, at: 0)
            if entries.count > 50 { entries = Array(entries.prefix(50)) }
            save()
            return entry
        }

        let entry = CaptureEntry(
            id: UUID(),
            filename: filename,
            originalFilename: filename,
            capturedAt: Date()
        )
        entries.insert(entry, at: 0)
        // Keep max 50
        if entries.count > 50 { entries = Array(entries.prefix(50)) }
        save()
        return entry
    }

    public func rename(id: UUID, to newName: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let oldFilename = entries[index].filename
        let ext = (oldFilename as NSString).pathExtension
        let newFilename = "\(newName).\(ext)"

        let oldURL = capturesDir.appendingPathComponent(oldFilename)
        let newURL = capturesDir.appendingPathComponent(newFilename)

        do {
            try fileManager.moveItem(at: oldURL, to: newURL)
            entries[index].filename = newFilename
            save()
        } catch {}
    }

    public func delete(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let url = capturesDir.appendingPathComponent(entries[index].filename)
        try? fileManager.removeItem(at: url)
        entries.remove(at: index)
        save()
    }

    public func path(for entry: CaptureEntry) -> String {
        capturesDir.appendingPathComponent(entry.filename).path
    }

    public func thumbnailURL(for entry: CaptureEntry) -> URL {
        capturesDir.appendingPathComponent(entry.filename)
    }

    public nonisolated func thumbnailAsync(for url: URL, id: UUID, maxPixelSize: CGFloat = 120) async -> NSImage? {
        let key = "\(id.uuidString)-\(Int(maxPixelSize))"
        if let cached = ThumbnailCache.shared.object(forKey: key as NSString) { return cached }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                          kCGImageSourceCreateThumbnailWithTransform: true
                      ] as CFDictionary) else {
                    continuation.resume(returning: nil)
                    return
                }

                let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                ThumbnailCache.shared.setObject(image, forKey: key as NSString)
                continuation.resume(returning: image)
            }
        }
    }

    public func invalidateThumbnail(for id: UUID) {
        let key = "\(id.uuidString)-120" as NSString
        ThumbnailCache.shared.removeObject(forKey: key)
    }

    public func clearAll() {
        for entry in entries {
            let url = capturesDir.appendingPathComponent(entry.filename)
            try? fileManager.removeItem(at: url)
        }
        entries.removeAll()
        save()
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}
