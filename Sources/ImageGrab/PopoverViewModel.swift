import AppKit
import Foundation

@MainActor
public final class PopoverViewModel: ObservableObject {
    @Published public var entries: [CaptureEntry] = []

    private let store: CaptureStore

    public init(store: CaptureStore) {
        self.store = store
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
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("repos/ImageGrab/captures")
        NSWorkspace.shared.open(url)
    }

    public func thumbnailImage(for entry: CaptureEntry) -> NSImage? {
        store.thumbnail(for: entry)
    }

    public func fullPath(for entry: CaptureEntry) -> String {
        store.path(for: entry)
    }
}
