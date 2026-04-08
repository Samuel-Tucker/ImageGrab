import AppKit
import Foundation

public struct CaptureEntry: Codable, Identifiable, Sendable {
    public let id: UUID
    public var filename: String
    public let originalFilename: String
    public let capturedAt: Date
    public var aiNamed: Bool
}

@MainActor
public final class CaptureStore {
    public private(set) var entries: [CaptureEntry] = []
    private let capturesDir: URL
    private let metadataURL: URL

    public init() {
        let appSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let base = appSupport
            .appendingPathComponent("ImageGrab", isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
        capturesDir = base
        metadataURL = base.appendingPathComponent(".metadata.json")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        load()
    }

    public func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([CaptureEntry].self, from: data) else { return }
        // Only keep entries whose files still exist
        entries = decoded.filter { FileManager.default.fileExists(atPath: capturesDir.appendingPathComponent($0.filename).path) }
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: metadataURL)
    }

    @discardableResult
    public func addCapture(image: NSImage) -> CaptureEntry? {
        let timestamp = Self.timestampFormatter.string(from: Date())
        let filename = availableFilename(baseName: "capture-\(timestamp)", pathExtension: "png")
        let url = capturesDir.appendingPathComponent(filename)

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }

        do {
            try pngData.write(to: url)
        } catch {
            return nil
        }

        let entry = CaptureEntry(
            id: UUID(),
            filename: filename,
            originalFilename: filename,
            capturedAt: Date(),
            aiNamed: false
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
        let newFilename = availableFilename(
            baseName: newName,
            pathExtension: ext,
            excluding: oldFilename
        )

        let oldURL = capturesDir.appendingPathComponent(oldFilename)
        let newURL = capturesDir.appendingPathComponent(newFilename)

        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            entries[index].filename = newFilename
            entries[index].aiNamed = true
            save()
        } catch {}
    }

    public func delete(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let url = capturesDir.appendingPathComponent(entries[index].filename)
        try? FileManager.default.removeItem(at: url)
        entries.remove(at: index)
        save()
    }

    public func path(for entry: CaptureEntry) -> String {
        capturesDir.appendingPathComponent(entry.filename).path
    }

    public var capturesDirectoryURL: URL {
        capturesDir
    }

    public func thumbnail(for entry: CaptureEntry, size: NSSize = NSSize(width: 60, height: 60)) -> NSImage? {
        let url = capturesDir.appendingPathComponent(entry.filename)
        guard let image = NSImage(contentsOf: url) else { return nil }
        let thumb = NSImage(size: size)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        thumb.unlockFocus()
        return thumb
    }

    public func clearAll() {
        for entry in entries {
            let url = capturesDir.appendingPathComponent(entry.filename)
            try? FileManager.default.removeItem(at: url)
        }
        entries.removeAll()
        save()
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return f
    }()

    private func availableFilename(baseName: String, pathExtension: String, excluding existingFilename: String? = nil) -> String {
        let sanitizedBaseName = Self.sanitizeBaseName(baseName)
        let ext = pathExtension.isEmpty ? "" : ".\(pathExtension)"

        var suffix = 1
        var candidate = sanitizedBaseName + ext
        while candidate != existingFilename &&
                FileManager.default.fileExists(atPath: capturesDir.appendingPathComponent(candidate).path) {
            suffix += 1
            candidate = "\(sanitizedBaseName)-\(suffix)\(ext)"
        }
        return candidate
    }

    private static func sanitizeBaseName(_ rawValue: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\")
        let cleaned = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")

        return cleaned.isEmpty ? "capture" : cleaned
    }
}
