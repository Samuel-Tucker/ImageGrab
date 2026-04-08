import AppKit
import Foundation

@MainActor
public final class PopoverViewModel: ObservableObject {
    @Published public var entries: [CaptureEntry] = []
    @Published public var isAccessibilityTrusted: Bool

    /// Called when a drag starts so the popover can stay open during the session
    public var onDragStarted: (() -> Void)?
    public var onRequestAccessibilityAccess: (() -> Void)?

    private let store: CaptureStore

    public init(store: CaptureStore, isAccessibilityTrusted: Bool) {
        self.store = store
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.entries = store.entries
    }

    public func refresh() {
        entries = store.entries
    }

    public func copyPath(for entry: CaptureEntry) {
        let path = store.path(for: entry)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    public func delete(id: UUID) {
        store.delete(id: id)
        refresh()
    }

    public func rename(id: UUID, to name: String) {
        store.rename(id: id, to: name)
        refresh()
    }

    public func clearAll() {
        store.clearAll()
        refresh()
    }

    public func openFolder() {
        NSWorkspace.shared.open(store.capturesDirectoryURL)
    }

    public func requestAccessibilityAccess() {
        onRequestAccessibilityAccess?()
    }

    public func updateAccessibilityTrust(_ isTrusted: Bool) {
        isAccessibilityTrusted = isTrusted
    }

    public func thumbnailImage(for entry: CaptureEntry) -> NSImage? {
        store.thumbnail(for: entry, size: NSSize(width: 120, height: 120))
    }

    public func fullPath(for entry: CaptureEntry) -> String {
        store.path(for: entry)
    }
}
