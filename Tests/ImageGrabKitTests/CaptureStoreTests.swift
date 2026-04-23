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
        XCTAssertTrue(["png", "webp"].contains((entry.filename as NSString).pathExtension))
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

    func testRenameMovesUnderlyingFile() throws {
        let capturesDirectory = try makeCapturesDirectory()
        defer { try? FileManager.default.removeItem(at: capturesDirectory) }

        let store = CaptureStore(capturesDirectory: capturesDirectory)
        let entry = try XCTUnwrap(store.addCapture(image: makeImage()))
        let originalPath = store.path(for: entry)
        let ext = (entry.filename as NSString).pathExtension

        store.rename(id: entry.id, to: "renamed-capture")

        let renamedEntry = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(renamedEntry.filename, "renamed-capture.\(ext)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.path(for: renamedEntry)))
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
