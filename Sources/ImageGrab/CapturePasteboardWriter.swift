import AppKit

enum CapturePasteboardWriter {
    @discardableResult
    static func copyImage(_ image: NSImage, savedPath path: String?, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let pngData = pngData(for: image) else { return false }

        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)

        if let path {
            item.setString(path, forType: .string)
            item.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL)
        }

        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    private static func pngData(for image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}
