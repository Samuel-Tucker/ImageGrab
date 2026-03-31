import AppKit
import Foundation
import ImageIO

@MainActor
public final class PopoverViewModel: ObservableObject {
    @Published public var entries: [CaptureEntry] = []

    /// Called when a drag starts so the popover can stay open during the session
    public var onDragStarted: (() -> Void)?

    private let store: CaptureStore
    private var currentQuickViewPanel: QuickViewPanel?
    private var currentQuickViewEntryID: UUID?

    public init(store: CaptureStore) {
        self.store = store
        self.entries = store.entries
    }

    public func refresh() {
        entries = store.entries
        syncQuickViewIfNeeded()
    }

    public func copyPath(for entry: CaptureEntry) {
        let path = store.path(for: entry)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    public func delete(id: UUID) {
        if currentQuickViewEntryID == id {
            dismissQuickView()
        }
        store.delete(id: id)
        refresh()
    }

    public func rename(id: UUID, to name: String) {
        store.rename(id: id, to: name)
        refresh()
    }

    public func clearAll() {
        dismissQuickView()
        store.clearAll()
        refresh()
    }

    public func openFolder() {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("repos/ImageGrab/captures")
        NSWorkspace.shared.open(url)
    }

    public func thumbnailImage(for entry: CaptureEntry) -> NSImage? {
        store.thumbnail(for: entry, size: NSSize(width: 120, height: 120))
    }

    public func fullPath(for entry: CaptureEntry) -> String {
        store.path(for: entry)
    }

    public func showQuickView(for entry: CaptureEntry) {
        if currentQuickViewEntryID == entry.id, currentQuickViewPanel != nil {
            dismissQuickView()
            return
        }

        guard let image = decodedImage(for: entry) else {
            dismissQuickView()
            NSSound.beep()
            return
        }

        currentQuickViewEntryID = entry.id
        let screen = activeScreen()

        if let panel = currentQuickViewPanel {
            panel.update(image: image, filename: entry.filename, screen: screen, centerOnScreen: false)
            panel.show()
            return
        }

        let panel = QuickViewPanel(image: image, filename: entry.filename, screen: screen)
        panel.onClose = { [weak self, weak panel] in
            guard let self else { return }
            if self.currentQuickViewPanel === panel {
                self.clearQuickViewReferences()
            }
        }

        currentQuickViewPanel = panel
        panel.show()
    }

    public func dismissQuickView() {
        let panel = currentQuickViewPanel
        clearQuickViewReferences()
        panel?.close()
    }

    private func syncQuickViewIfNeeded() {
        guard let viewedEntryID = currentQuickViewEntryID else { return }
        guard let panel = currentQuickViewPanel else {
            clearQuickViewReferences()
            return
        }
        guard let entry = entries.first(where: { $0.id == viewedEntryID }),
              let image = decodedImage(for: entry) else {
            dismissQuickView()
            return
        }

        panel.update(image: image, filename: entry.filename, screen: panel.screen, centerOnScreen: false)
    }

    private func decodedImage(for entry: CaptureEntry) -> NSImage? {
        let url = URL(fileURLWithPath: store.path(for: entry))
        guard FileManager.default.fileExists(atPath: url.path),
              let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        )
    }

    private func clearQuickViewReferences() {
        currentQuickViewPanel = nil
        currentQuickViewEntryID = nil
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
    }
}
