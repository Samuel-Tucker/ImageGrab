import AppKit
import Foundation
import ImageIO

@MainActor
public final class PopoverViewModel: ObservableObject {
    @Published public var entries: [CaptureEntry] = []

    /// Called when a drag starts so the popover can stay open during the session
    public var onDragStarted: (() -> Void)?

    /// Called to keep/release the popover while quick view is open
    public var onQuickViewOpened: (() -> Void)?
    public var onQuickViewClosed: ((QuickViewCloseReason) -> Void)?

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
        store.invalidateThumbnail(for: id)
        store.delete(id: id)
        refresh()
    }

    public func clearAll() {
        dismissQuickView()
        store.clearAll()
        refresh()
    }

    public func openFolder() {
        NSWorkspace.shared.open(store.capturesDirectory)
    }

    public func thumbnailImage(for entry: CaptureEntry) async -> NSImage? {
        let url = store.thumbnailURL(for: entry)
        return await store.thumbnailAsync(for: url, id: entry.id)
    }

    public func fullPath(for entry: CaptureEntry) -> String {
        store.path(for: entry)
    }

    public func dragURL(for entry: CaptureEntry) -> URL {
        store.dragURL(for: entry)
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
        panel.onClose = { [weak self, weak panel] reason in
            guard let self else { return }
            if self.currentQuickViewPanel === panel {
                self.clearQuickViewReferences(reason: reason)
            }
        }

        currentQuickViewPanel = panel
        panel.show()
        onQuickViewOpened?()
    }

    public func dismissQuickView() {
        let panel = currentQuickViewPanel
        clearQuickViewReferences(reason: .programmatic)
        panel?.closeProgrammatically()
    }

    private func syncQuickViewIfNeeded() {
        guard let viewedEntryID = currentQuickViewEntryID else { return }
        guard let panel = currentQuickViewPanel else {
            clearQuickViewReferences(reason: .window)
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

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let pointSize = NSSize(
            width: CGFloat(cgImage.width) / scale,
            height: CGFloat(cgImage.height) / scale
        )
        return NSImage(cgImage: cgImage, size: pointSize)
    }

    private func clearQuickViewReferences(reason: QuickViewCloseReason) {
        currentQuickViewPanel = nil
        currentQuickViewEntryID = nil
        onQuickViewClosed?(reason)
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
    }
}
