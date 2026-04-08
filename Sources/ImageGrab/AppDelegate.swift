import AppKit
import Carbon
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum DefaultsKeys {
        static let accessibilityPrompted = "ImageGrab.accessibilityPrompted"
    }

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
        DispatchQueue.main.async { [weak self] in
            self?.refreshAccessibilityStatus()
            self?.showAccessibilityHelpIfNeeded(promptSystem: self?.shouldPromptForAccessibility() ?? false)
        }
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
        let vm = PopoverViewModel(
            store: captureStore,
            isAccessibilityTrusted: AccessibilityPermissionManager.isTrusted()
        )
        vm.onRequestAccessibilityAccess = { [weak self] in
            self?.showAccessibilityHelpIfNeeded(promptSystem: true)
        }
        viewModel = vm

        let p = NSPopover()
        p.contentSize = NSSize(width: 300, height: 400)
        p.behavior = .transient
        p.contentViewController = NSHostingController(rootView: ImageGrabPopoverView(viewModel: vm))
        popover = p

        // Keep popover open during drag sessions so cross-app drops work
        vm.onDragStarted = { [weak self] in
            self?.popover?.behavior = .applicationDefined
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self?.popover?.behavior = .transient
            }
        }
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        refreshAccessibilityStatus()
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

    private var clipboardPollTimer: Timer?

    private func startCapture() {
        guard AccessibilityPermissionManager.isTrusted() else {
            showAccessibilityHelpIfNeeded(promptSystem: false)
            NSSound.beep()
            return
        }

        // Close popover if open
        popover?.performClose(nil)

        // Record current clipboard state, then simulate Cmd+Shift+Ctrl+4
        // This triggers the native macOS screenshot-to-clipboard crosshair.
        // Requires Accessibility permission, NOT Screen Recording.
        let initialChangeCount = NSPasteboard.general.changeCount

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x15, keyDown: true)  // 0x15 = kVK_ANSI_4
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x15, keyDown: false)
        let flags: CGEventFlags = [.maskCommand, .maskShift, .maskControl]
        keyDown?.flags = flags
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // Poll clipboard for the new screenshot
        let startTime = Date()
        clipboardPollTimer?.invalidate()
        clipboardPollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            let pasteboard = NSPasteboard.general
            if pasteboard.changeCount != initialChangeCount {
                timer.invalidate()
                Task { @MainActor [weak self] in
                    self?.handleClipboardCapture()
                }
            } else if Date().timeIntervalSince(startTime) > 30 {
                // Timeout — user likely cancelled
                timer.invalidate()
            }
        }
    }

    private func handleClipboardCapture() {
        guard let image = NSImage(pasteboard: NSPasteboard.general) else {
            NSSound.beep()
            return
        }

        let preview = CapturePreviewWindow(
            image: image,
            onSave: { [weak self] img, copyPath in
                self?.handleCapturedImage(img, copyPath: copyPath)
                self?.previewWindow = nil
            },
            onCancel: { [weak self] in
                self?.previewWindow = nil
            }
        )
        self.previewWindow = preview
        preview.show()
    }

    private func handleCapturedImage(_ image: NSImage, copyPath: Bool = false) {
        guard let entry = captureStore.addCapture(image: image) else {
            NSSound.beep()
            return
        }

        if copyPath {
            let path = captureStore.path(for: entry)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        }

        viewModel?.refresh()

        // Show popover as feedback
        if let button = statusItem?.button, let popover, !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }

        // AI rename in background (vision model sees the actual screenshot)
        let imagePath = captureStore.path(for: entry)
        Task {
            let imageURL = URL(fileURLWithPath: imagePath)
            if let suggestion = await aiRenamer.suggestName(for: entry.filename, imageURL: imageURL) {
                captureStore.rename(id: entry.id, to: suggestion)
                viewModel?.refresh()
            }
        }
    }

    private func refreshAccessibilityStatus() {
        let isTrusted = AccessibilityPermissionManager.isTrusted()
        if isTrusted {
            UserDefaults.standard.set(true, forKey: DefaultsKeys.accessibilityPrompted)
        }
        viewModel?.updateAccessibilityTrust(isTrusted)
    }

    private func shouldPromptForAccessibility() -> Bool {
        guard !AccessibilityPermissionManager.isTrusted() else { return false }
        return !UserDefaults.standard.bool(forKey: DefaultsKeys.accessibilityPrompted)
    }

    private func showAccessibilityHelpIfNeeded(promptSystem: Bool) {
        let isTrusted = AccessibilityPermissionManager.isTrusted(prompt: promptSystem)
        if promptSystem {
            UserDefaults.standard.set(true, forKey: DefaultsKeys.accessibilityPrompted)
        }
        viewModel?.updateAccessibilityTrust(isTrusted)
        guard !isTrusted else { return }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Enable Accessibility for ImageGrab"
        alert.informativeText = """
        ImageGrab needs Accessibility access to trigger the macOS screenshot crosshair when you press Ctrl+Option+G.

        macOS will list ImageGrab in Privacy & Security > Accessibility. Turn it on there, then return to ImageGrab and try again.
        """
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Not Now")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            AccessibilityPermissionManager.openSettings()
        }
    }
}
