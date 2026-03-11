import AppKit
import Carbon
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let captureStore = CaptureStore()
    private let aiRenamer = AIRenamer()
    private let hotKeyManager = GlobalHotKeyManager()
    private var viewModel: PopoverViewModel?

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var previewWindow: CapturePreviewWindow?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        registerHotKey()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregisterAll()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ImageGrab") {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "IG"
        }
        item.button?.action = #selector(togglePopover)
        item.button?.target = self
        statusItem = item
    }

    private func setupPopover() {
        let vm = PopoverViewModel(store: captureStore)
        viewModel = vm

        let p = NSPopover()
        p.contentSize = NSSize(width: 300, height: 400)
        p.behavior = .transient
        p.contentViewController = NSHostingController(rootView: ImageGrabPopoverView(viewModel: vm))
        popover = p
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            viewModel?.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func registerHotKey() {
        // Ctrl+Opt+G
        let modifiers = UInt32(controlKey | optionKey)
        let keyCode = UInt32(kVK_ANSI_G)
        _ = hotKeyManager.register(keyCode: keyCode, modifiers: modifiers) { [weak self] in
            Task { @MainActor in
                self?.startCapture()
            }
        }
    }

    private func startCapture() {
        // Close popover if open
        popover?.performClose(nil)

        let tmpPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("imagegrab-\(UUID().uuidString).png").path

        // Use native screencapture -i (interactive crosshair, no permission needed)
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-x", tmpPath]

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return
            }

            // User cancelled (Escape) — no file created
            guard FileManager.default.fileExists(atPath: tmpPath) else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard let image = NSImage(contentsOfFile: tmpPath) else {
                    try? FileManager.default.removeItem(atPath: tmpPath)
                    return
                }

                // Clean up temp file
                try? FileManager.default.removeItem(atPath: tmpPath)

                // Show preview window for review
                let preview = CapturePreviewWindow(
                    image: image,
                    onSave: { [weak self] img in
                        self?.handleCapturedImage(img)
                        self?.previewWindow = nil
                    },
                    onCancel: { [weak self] in
                        self?.previewWindow = nil
                    }
                )
                self.previewWindow = preview
                preview.show()
            }
        }
    }

    private func handleCapturedImage(_ image: NSImage) {
        guard let entry = captureStore.addCapture(image: image) else {
            NSSound.beep()
            return
        }

        viewModel?.refresh()

        // Show popover as feedback
        if let button = statusItem?.button, let popover, !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }

        // AI rename in background
        Task {
            if let suggestion = await aiRenamer.suggestName(for: entry.filename) {
                captureStore.rename(id: entry.id, to: suggestion)
                viewModel?.refresh()
            }
        }
    }
}
