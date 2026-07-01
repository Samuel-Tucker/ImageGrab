import AppKit
import XCTest
@testable import ImageGrabKit

@MainActor
final class CaptureStoreTests: XCTestCase {
    func testAddCapturePersistsMetadataAndThumbnail() async throws {
        let capturesDirectory = try makeCapturesDirectory()
        defer { try? FileManager.default.removeItem(at: capturesDirectory) }

        let store = CaptureStore(capturesDirectory: capturesDirectory)
        let entry = try XCTUnwrap(store.addCapture(image: makeImage()))

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.path(for: entry)))
        XCTAssertEqual((entry.filename as NSString).pathExtension, "png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: capturesDirectory.appendingPathComponent(".metadata.json").path))

        let thumbnail = await store.thumbnailAsync(for: store.thumbnailURL(for: entry), id: entry.id)
        XCTAssertNotNil(thumbnail)
    }

    func testLoadFiltersMissingFilesFromMetadata() throws {
        let capturesDirectory = try makeCapturesDirectory()
        defer { try? FileManager.default.removeItem(at: capturesDirectory) }

        let existing = CaptureEntry(
            id: UUID(),
            filename: "existing.png",
            originalFilename: "existing.png",
            capturedAt: Date()
        )
        let missing = CaptureEntry(
            id: UUID(),
            filename: "missing.png",
            originalFilename: "missing.png",
            capturedAt: Date()
        )

        try pngData().write(to: capturesDirectory.appendingPathComponent(existing.filename))
        let metadata = try JSONEncoder().encode([existing, missing])
        try metadata.write(to: capturesDirectory.appendingPathComponent(".metadata.json"))

        let store = CaptureStore(capturesDirectory: capturesDirectory)

        XCTAssertEqual(store.entries.map(\.filename), [existing.filename])
    }

    func testDeleteRemovesEntryAndFile() throws {
        let capturesDirectory = try makeCapturesDirectory()
        defer { try? FileManager.default.removeItem(at: capturesDirectory) }

        let store = CaptureStore(capturesDirectory: capturesDirectory)
        let entry = try XCTUnwrap(store.addCapture(image: makeImage()))
        let path = store.path(for: entry)

        store.delete(id: entry.id)

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testDragURLUsesPNGFile() throws {
        let capturesDirectory = try makeCapturesDirectory()
        defer { try? FileManager.default.removeItem(at: capturesDirectory) }

        let store = CaptureStore(capturesDirectory: capturesDirectory)
        let entry = try XCTUnwrap(store.addCapture(image: makeImage()))

        let dragURL = store.dragURL(for: entry)

        XCTAssertEqual(dragURL.pathExtension, "png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dragURL.path))
    }

    func testDeleteRemovesLegacyDragExport() throws {
        let capturesDirectory = try makeCapturesDirectory()
        defer { try? FileManager.default.removeItem(at: capturesDirectory) }

        let entry = CaptureEntry(
            id: UUID(),
            filename: "legacy-capture.webp",
            originalFilename: "legacy-capture.webp",
            capturedAt: Date()
        )
        try pngData().write(to: capturesDirectory.appendingPathComponent(entry.filename))
        try JSONEncoder().encode([entry]).write(to: capturesDirectory.appendingPathComponent(".metadata.json"))

        let store = CaptureStore(capturesDirectory: capturesDirectory)
        let loadedEntry = try XCTUnwrap(store.entries.first)
        let dragURL = store.dragURL(for: loadedEntry)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dragURL.path))

        store.delete(id: loadedEntry.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: dragURL.path))
    }

    func testClearAllRemovesLegacyDragExportDirectory() throws {
        let capturesDirectory = try makeCapturesDirectory()
        defer { try? FileManager.default.removeItem(at: capturesDirectory) }

        let entry = CaptureEntry(
            id: UUID(),
            filename: "legacy-capture.webp",
            originalFilename: "legacy-capture.webp",
            capturedAt: Date()
        )
        try pngData().write(to: capturesDirectory.appendingPathComponent(entry.filename))
        try JSONEncoder().encode([entry]).write(to: capturesDirectory.appendingPathComponent(".metadata.json"))

        let store = CaptureStore(capturesDirectory: capturesDirectory)
        let loadedEntry = try XCTUnwrap(store.entries.first)
        let dragURL = store.dragURL(for: loadedEntry)
        let exportDirectory = dragURL.deletingLastPathComponent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportDirectory.path))

        store.clearAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: exportDirectory.path))
    }

    func testAddCaptureAvoidsFilenameCollisionWithinSameSecond() throws {
        let capturesDirectory = try makeCapturesDirectory()
        defer { try? FileManager.default.removeItem(at: capturesDirectory) }

        let store = CaptureStore(capturesDirectory: capturesDirectory)
        let first = try XCTUnwrap(store.addCapture(image: makeImage()))
        let second = try XCTUnwrap(store.addCapture(image: makeImage()))

        XCTAssertNotEqual(first.filename, second.filename)
        XCTAssertEqual(Set(store.entries.map(\.filename)).count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.path(for: first)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.path(for: second)))
    }

    func testAddCaptureUsesPreferredBaseName() throws {
        let capturesDirectory = try makeCapturesDirectory()
        defer { try? FileManager.default.removeItem(at: capturesDirectory) }

        let store = CaptureStore(capturesDirectory: capturesDirectory)
        let entry = try XCTUnwrap(store.addCapture(image: makeImage(), preferredBaseName: "Important Screenshot"))

        XCTAssertEqual(entry.filename, "Important Screenshot.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.path(for: entry)))
    }

    func testAddCaptureSanitizesPreferredBaseNameAndAvoidsCollision() throws {
        let capturesDirectory = try makeCapturesDirectory()
        defer { try? FileManager.default.removeItem(at: capturesDirectory) }

        let store = CaptureStore(capturesDirectory: capturesDirectory)
        let first = try XCTUnwrap(store.addCapture(image: makeImage(), preferredBaseName: "foo/bar"))
        let second = try XCTUnwrap(store.addCapture(image: makeImage(), preferredBaseName: "foo/bar"))

        XCTAssertEqual(first.filename, "foobar.png")
        XCTAssertEqual(second.filename, "foobar-2.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.path(for: first)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.path(for: second)))
    }

    func testReplaceCaptureImageKeepsEntryAndUpdatesFile() throws {
        let capturesDirectory = try makeCapturesDirectory()
        defer { try? FileManager.default.removeItem(at: capturesDirectory) }

        let store = CaptureStore(capturesDirectory: capturesDirectory)
        let entry = try XCTUnwrap(store.addCapture(image: makeImage(width: 64, height: 48), preferredBaseName: "edited"))
        let originalAttributes = try FileManager.default.attributesOfItem(atPath: store.path(for: entry))
        let originalSize = try XCTUnwrap(originalAttributes[.size] as? NSNumber)

        XCTAssertTrue(store.replaceCaptureImage(id: entry.id, image: makeImage(width: 96, height: 72)))

        let updatedEntry = try XCTUnwrap(store.entries.first(where: { $0.id == entry.id }))
        let updatedAttributes = try FileManager.default.attributesOfItem(atPath: store.path(for: updatedEntry))
        let updatedSize = try XCTUnwrap(updatedAttributes[.size] as? NSNumber)

        XCTAssertEqual(updatedEntry.filename, "edited.png")
        XCTAssertNotEqual(originalSize, updatedSize)
    }

    func testCapturePasteboardWriterCopiesImageAndSavedPath() throws {
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name(rawValue: "CapturePasteboardWriterTests-image")))
        let path = "/tmp/ImageGrabTests/copied.png"

        XCTAssertTrue(CapturePasteboardWriter.copyImage(makeImage(), savedPath: path, to: pasteboard))

        let item = try XCTUnwrap(pasteboard.pasteboardItems?.first)
        XCTAssertNotNil(item.data(forType: .png))
        XCTAssertEqual(item.string(forType: .string), path)
        XCTAssertEqual(item.string(forType: .fileURL), URL(fileURLWithPath: path).absoluteString)
    }

    func testClearAllRemovesTrackedFiles() throws {
        let capturesDirectory = try makeCapturesDirectory()
        defer { try? FileManager.default.removeItem(at: capturesDirectory) }

        let first = CaptureEntry(
            id: UUID(),
            filename: "first.png",
            originalFilename: "first.png",
            capturedAt: Date()
        )
        let second = CaptureEntry(
            id: UUID(),
            filename: "second.png",
            originalFilename: "second.png",
            capturedAt: Date()
        )

        try pngData().write(to: capturesDirectory.appendingPathComponent(first.filename))
        try pngData().write(to: capturesDirectory.appendingPathComponent(second.filename))
        let metadata = try JSONEncoder().encode([first, second])
        try metadata.write(to: capturesDirectory.appendingPathComponent(".metadata.json"))

        let store = CaptureStore(capturesDirectory: capturesDirectory)
        store.clearAll()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: capturesDirectory.appendingPathComponent(first.filename).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: capturesDirectory.appendingPathComponent(second.filename).path))

        let metadataData = try Data(contentsOf: capturesDirectory.appendingPathComponent(".metadata.json"))
        let decoded = try JSONDecoder().decode([CaptureEntry].self, from: metadataData)
        XCTAssertTrue(decoded.isEmpty)
    }

    private func makeCapturesDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageGrabTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeImage(width: Int = 64, height: Int = 48) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }

    private func pngData() throws -> Data {
        let image = makeImage()
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw XCTSkip("Failed to generate PNG fixture")
        }
        return pngData
    }
}
