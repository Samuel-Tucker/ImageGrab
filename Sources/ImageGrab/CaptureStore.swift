import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

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
        let base = capturesDirectory ?? Self.defaultCapturesDirectory(fileManager: fileManager)
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
        let url = uniqueCaptureURL(baseName: "capture-\(timestamp)", extension: "png")
        let filename = url.lastPathComponent

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        guard writePNG(cgImage, to: url) else { return nil }

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

    public func delete(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let url = capturesDir.appendingPathComponent(entries[index].filename)
        try? fileManager.removeItem(at: url)
        try? fileManager.removeItem(at: dragExportURL(for: entries[index]))
        entries.remove(at: index)
        save()
    }

    public func path(for entry: CaptureEntry) -> String {
        capturesDir.appendingPathComponent(entry.filename).path
    }

    public func thumbnailURL(for entry: CaptureEntry) -> URL {
        capturesDir.appendingPathComponent(entry.filename)
    }

    public var capturesDirectory: URL {
        capturesDir
    }

    public func dragURL(for entry: CaptureEntry) -> URL {
        let sourceURL = capturesDir.appendingPathComponent(entry.filename)
        let ext = sourceURL.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "heic", "heif"].contains(ext) {
            return sourceURL
        }

        let exportDirectory = dragExportDirectory()
        try? fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let exportURL = dragExportURL(for: entry)

        if fileManager.fileExists(atPath: exportURL.path) {
            return exportURL
        }

        guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              writePNG(cgImage, to: exportURL) else {
            return sourceURL
        }
        return exportURL
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
        try? fileManager.removeItem(at: dragExportDirectory())
        entries.removeAll()
        save()
    }

    private func uniqueCaptureURL(baseName: String, extension ext: String) -> URL {
        var candidate = capturesDir
            .appendingPathComponent(baseName)
            .appendingPathExtension(ext)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = capturesDir
                .appendingPathComponent("\(baseName)-\(suffix)")
                .appendingPathExtension(ext)
            suffix += 1
        }
        return candidate
    }

    private func dragExportDirectory() -> URL {
        capturesDir.appendingPathComponent(".drag-exports", isDirectory: true)
    }

    private func dragExportURL(for entry: CaptureEntry) -> URL {
        dragExportDirectory()
            .appendingPathComponent((entry.filename as NSString).deletingPathExtension)
            .appendingPathExtension("png")
    }

    private func writePNG(_ cgImage: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        return CGImageDestinationFinalize(destination)
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    private static func defaultCapturesDirectory(fileManager: FileManager) -> URL {
        let legacyURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("repos/ImageGrab/captures")
        if fileManager.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("ImageGrab", isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
    }
}
