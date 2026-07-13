import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
public final class PopoverViewModel: ObservableObject {
    @Published public var entries: [CaptureEntry] = []
    @Published public var captureDelay: CaptureDelay = .none
    @Published public var lastCaptureRegion: CaptureRegion?
    @Published public var hotKeyStatus = "Hotkeys: registering"
    @Published public var regionTapStatus = "Fn+G tap: starting"
    @Published public var permissionStatus = "Permissions: checking"
    @Published public var captureStatus = "Capture: idle"
    @Published public var isPopoverPinned = false

    public var canRepeatLastRegion: Bool {
        lastCaptureRegion?.isUsable == true
    }

    /// Called when a drag starts so the popover can stay open during the session
    public var onDragStarted: (() -> Void)?
    public var onPopoverPinnedChanged: ((Bool) -> Void)?
    public var onCaptureRegion: (() -> Void)?
    public var onCaptureFullScreen: (() -> Void)?
    public var onRepeatLastRegion: (() -> Void)?

    /// Called to keep/release the popover while quick view is open
    public var onQuickViewOpened: (() -> Void)?
    public var onQuickViewClosed: ((QuickViewCloseReason) -> Void)?

    private let store: CaptureStore
    private var currentQuickViewPanel: QuickViewPanel?
    private var currentQuickViewEntryID: UUID?
    private var currentEditWindow: CapturePreviewWindow?

    public init(store: CaptureStore) {
        self.store = store
        self.entries = store.entries
    }

    public func refresh() {
        entries = store.entries
        syncQuickViewIfNeeded()
    }

    public func updateHotKeyStatus(
        optionRegionRegistered: Bool,
        alternateRegionRegistered: Bool,
        fullScreenRegistered: Bool
    ) {
        let regionLabel: String
        switch (optionRegionRegistered, alternateRegionRegistered) {
        case (true, true):
            regionLabel = "Opt+G / Ctrl+Cmd+G"
        case (true, false):
            regionLabel = "Opt+G"
        case (false, true):
            regionLabel = "Ctrl+Cmd+G"
        case (false, false):
            regionLabel = "region failed"
        }

        let fullScreenLabel = fullScreenRegistered ? "Opt+Cmd+G" : "full screen failed"
        hotKeyStatus = "Hotkeys: \(regionLabel), \(fullScreenLabel)"
    }

    public func updateCaptureStatus(_ status: String) {
        captureStatus = status
    }

    public func updateRegionTapStatus(enabled: Bool) {
        regionTapStatus = enabled
            ? "Fn+G / Opt+G tap: ready"
            : "Fn+G / Opt+G tap: blocked, check Accessibility"
    }

    public func updatePermissionStatus(accessibility: Bool, inputMonitoring: Bool) {
        switch (accessibility, inputMonitoring) {
        case (true, true):
            permissionStatus = "Permissions: Accessibility and Input Monitoring ready"
        case (false, true):
            permissionStatus = "Permissions: enable Accessibility"
        case (true, false):
            permissionStatus = "Permissions: enable Input Monitoring"
        case (false, false):
            permissionStatus = "Permissions: enable Accessibility and Input Monitoring"
        }
    }

    public func copyPath(for entry: CaptureEntry) {
        CapturePasteboardWriter.copyImageFile(at: URL(fileURLWithPath: store.path(for: entry)))
    }

    @discardableResult
    public func copyImages(for entries: [CaptureEntry]) -> Bool {
        let urls = entries.map { dragURL(for: $0) }
        guard CapturePasteboardWriter.copyImageFiles(at: urls) else {
            NSSound.beep()
            return false
        }
        return true
    }

    @discardableResult
    public func copyText(for entry: CaptureEntry) async -> Bool {
        let url = URL(fileURLWithPath: store.path(for: entry))
        do {
            let text = try await TextRecognizer.recognizeText(at: url)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                NSSound.beep()
                return false
            }

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    public func rename(id: UUID, to newBaseName: String) -> Bool {
        store.invalidateThumbnail(for: id)
        let success = store.rename(id: id, to: newBaseName)
        refresh()
        return success
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

    public func captureRegion() {
        onCaptureRegion?()
    }

    public func captureFullScreen() {
        onCaptureFullScreen?()
    }

    public func repeatLastRegion() {
        guard canRepeatLastRegion else {
            NSSound.beep()
            return
        }
        onRepeatLastRegion?()
    }

    public func togglePopoverPinned() {
        isPopoverPinned.toggle()
        onPopoverPinnedChanged?(isPopoverPinned)
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

    /// Builds the drag payload for a capture and signals `onDragStarted` so any
    /// presenting surface (popover or drop-down strip) can stay open for the
    /// duration of the drag. Registers the file URL, image data and a plain-text
    /// path so the capture drops into Finder, editors, browsers and terminals.
    public func makeDragProvider(for entry: CaptureEntry) -> NSItemProvider {
        onDragStarted?()

        let url = dragURL(for: entry)
        let provider = NSItemProvider()
        provider.suggestedName = url.lastPathComponent

        let imageType = UTType(filenameExtension: url.pathExtension) ?? .png

        provider.registerObject(url as NSURL, visibility: .all)
        provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
            completion(url.absoluteString.data(using: .utf8), nil)
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.url.identifier, visibility: .all) { completion in
            completion(url.absoluteString.data(using: .utf8), nil)
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: imageType.identifier, visibility: .all) { completion in
            do {
                completion(try Data(contentsOf: url), nil)
            } catch {
                completion(nil, error)
            }
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.image.identifier, visibility: .all) { completion in
            do {
                completion(try Data(contentsOf: url), nil)
            } catch {
                completion(nil, error)
            }
            return nil
        }
        provider.registerFileRepresentation(forTypeIdentifier: imageType.identifier, fileOptions: [], visibility: .all) { completion in
            completion(url, false, nil)
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
            completion(url.path.data(using: .utf8), nil)
            return nil
        }

        return provider
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

    public func editAnnotations(for entry: CaptureEntry) {
        guard let image = decodedImage(for: entry) else {
            NSSound.beep()
            return
        }

        dismissQuickView()

        let baseName = (entry.filename as NSString).deletingPathExtension
        let preview = CapturePreviewWindow(
            image: image,
            initialBaseName: baseName,
            onSave: { [weak self] editedImage, copyImage, requestedBaseName in
                guard let self else { return }

                let proposed = requestedBaseName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let current = (entry.filename as NSString).deletingPathExtension
                if !proposed.isEmpty, proposed != current, !self.rename(id: entry.id, to: proposed) {
                    NSSound.beep()
                    self.currentEditWindow = nil
                    return
                }

                guard self.store.replaceCaptureImage(id: entry.id, image: editedImage) else {
                    NSSound.beep()
                    self.currentEditWindow = nil
                    return
                }

                if copyImage, let updatedEntry = self.store.entries.first(where: { $0.id == entry.id }) {
                    let path = self.store.path(for: updatedEntry)
                    guard CapturePasteboardWriter.copyImage(editedImage, savedPath: path) else {
                        NSSound.beep()
                        self.currentEditWindow = nil
                        return
                    }
                }

                self.refresh()
                self.currentEditWindow = nil
            },
            onCancel: { [weak self] in
                self?.currentEditWindow = nil
            }
        )

        currentEditWindow = preview
        preview.show()
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
