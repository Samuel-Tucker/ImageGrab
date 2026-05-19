import AppKit
import Carbon
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let captureStore = CaptureStore()
    private var hotKeyManager: GlobalHotKeyManager?
    private var viewModel: PopoverViewModel?

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var popoverKeyDownMonitor: Any?
    private var regionHotKeyFallbackMonitor: Any?
    private var regionHotKeyEventTap: RegionHotKeyEventTap?
    private var previewWindow: CapturePreviewWindow?
    private var reopenPopoverAfterQuickView = false
    private var lastCaptureRegion: CaptureRegion?

    public override init() {
        super.init()
    }

    private enum CaptureMode {
        case region
        case fullScreen
        case lastRegion

        var statusLabel: String {
            switch self {
            case .region:
                "region"
            case .fullScreen:
                "full screen"
            case .lastRegion:
                "last region"
            }
        }
    }

    private enum ScreenCaptureRequest {
        case interactiveRegion
        case fullScreen
        case region(CaptureRegion)

        var screencaptureArguments: [String] {
            switch self {
            case .interactiveRegion:
                ["-i", "-c"]
            case .fullScreen:
                ["-c"]
            case .region(let region):
                ["-R\(region.screencaptureArgument)", "-c"]
            }
        }
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        registerHotKey()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        removePopoverKeyDownMonitor()
        removeRegionHotKeyFallbackMonitor()
        regionHotKeyEventTap?.stop()
        hotKeyManager?.unregisterAll()
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
        p.delegate = self
        p.contentViewController = NSHostingController(
            rootView: ImageGrabPopoverView(viewModel: vm) { [weak self] in
                self?.closePopover()
            }
        )
        popover = p

        // Keep popover open during drag sessions so cross-app drops work
        vm.onDragStarted = { [weak self] in
            self?.popover?.behavior = .applicationDefined
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                self?.popover?.behavior = .transient
            }
        }

        vm.onCaptureRegion = { [weak self] in
            self?.startCapture(.region)
        }

        vm.onCaptureFullScreen = { [weak self] in
            self?.startCapture(.fullScreen)
        }

        vm.onRepeatLastRegion = { [weak self] in
            self?.startCapture(.lastRegion)
        }

        // Quick View needs to sit above the thumbnail list. The macOS status-item
        // popover layer wins z-order fights, so close it and restore it on Esc.
        vm.onQuickViewOpened = { [weak self] in
            guard let self else { return }
            self.reopenPopoverAfterQuickView = self.popover?.isShown == true
            if self.reopenPopoverAfterQuickView {
                self.closePopover()
            }
        }
        vm.onQuickViewClosed = { [weak self] reason in
            guard let self else { return }
            guard self.reopenPopoverAfterQuickView, reason == .escape else {
                self.reopenPopoverAfterQuickView = false
                return
            }
            self.reopenPopoverAfterQuickView = false
            if let button = self.statusItem?.button {
                self.showPopover(relativeTo: button)
            }
        }
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            showPopover(relativeTo: button)
        }
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        guard let popover else { return }
        viewModel?.refresh()
        installPopoverKeyDownMonitor()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func closePopover() {
        popover?.performClose(nil)
        removePopoverKeyDownMonitor()
    }

    public func popoverDidClose(_ notification: Notification) {
        removePopoverKeyDownMonitor()
    }

    private func installPopoverKeyDownMonitor() {
        guard popoverKeyDownMonitor == nil else { return }
        popoverKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    self?.closePopover()
                }
                return nil
            }
            return event
        }
    }

    private func removePopoverKeyDownMonitor() {
        guard let monitor = popoverKeyDownMonitor else { return }
        NSEvent.removeMonitor(monitor)
        popoverKeyDownMonitor = nil
    }

    private func registerHotKey() {
        // Opt+G: region capture. Opt+Cmd+G: full-screen capture.
        let manager = GlobalHotKeyManager()
        hotKeyManager = manager
        let keyCode = UInt32(kVK_ANSI_G)

        let regionRegistered = manager.register(keyCode: keyCode, modifiers: UInt32(optionKey)) { [weak self] in
            Task { @MainActor in
                self?.startCapture(.region)
            }
        }

        let fullScreenRegistered = manager.register(keyCode: keyCode, modifiers: UInt32(optionKey | cmdKey)) { [weak self] in
            Task { @MainActor in
                self?.startCapture(.fullScreen)
            }
        }

        viewModel?.updateHotKeyStatus(
            regionRegistered: regionRegistered,
            fullScreenRegistered: fullScreenRegistered
        )
        installRegionHotKeyFallbackMonitor()
        installRegionHotKeyEventTap()
        NSLog("ImageGrab: region hotkey registration \(regionRegistered ? "succeeded" : "FAILED")")
        NSLog("ImageGrab: full-screen hotkey registration \(fullScreenRegistered ? "succeeded" : "FAILED")")
    }

    private func installRegionHotKeyFallbackMonitor() {
        guard regionHotKeyFallbackMonitor == nil else { return }
        regionHotKeyFallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == kVK_ANSI_G else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.option),
                  !flags.contains(.command),
                  !flags.contains(.shift),
                  !flags.contains(.control) else { return }
            Task { @MainActor in
                self?.viewModel?.updateCaptureStatus("Capture: Opt+G fallback received")
                self?.startCapture(.region)
            }
        }
    }

    private func removeRegionHotKeyFallbackMonitor() {
        guard let monitor = regionHotKeyFallbackMonitor else { return }
        NSEvent.removeMonitor(monitor)
        regionHotKeyFallbackMonitor = nil
    }

    private func installRegionHotKeyEventTap() {
        guard regionHotKeyEventTap == nil else { return }
        let tap = RegionHotKeyEventTap { [weak self] in
            Task { @MainActor in
                self?.viewModel?.updateCaptureStatus("Capture: Opt+G event tap received")
                self?.startCapture(.region)
            }
        }
        let enabled = tap.start()
        regionHotKeyEventTap = enabled ? tap : nil
        viewModel?.updateRegionTapStatus(enabled: enabled)
    }

    private var clipboardPollTimer: Timer?
    private var isCaptureInProgress = false
    private var captureLastSeenChangeCount = 0
    private var captureProcessID: Int32?
    private var pendingCountdownPanel: CaptureCountdownPanel?

    private func startCapture(_ mode: CaptureMode) {
        // While a countdown is pending, re-triggering the same hotkey cancels it.
        if pendingCountdownPanel != nil {
            cancelPendingCountdown()
            return
        }
        guard !isCaptureInProgress else { return }
        isCaptureInProgress = true

        // Close popover if open
        closePopover()
        viewModel?.updateCaptureStatus("Capture: requested \(mode.statusLabel)")

        switch mode {
        case .region:
            beginCaptureAfterOptionalDelay(.interactiveRegion)
        case .lastRegion:
            guard let lastCaptureRegion else {
                NSSound.beep()
                resetCaptureState()
                return
            }
            beginCaptureAfterOptionalDelay(.region(lastCaptureRegion))
        case .fullScreen:
            beginCaptureAfterOptionalDelay(.fullScreen)
        }
    }

    private func beginCaptureAfterOptionalDelay(_ request: ScreenCaptureRequest) {
        let delaySeconds = viewModel?.captureDelay.seconds ?? 0
        if delaySeconds > 0 {
            let panel = CaptureCountdownPanel(seconds: delaySeconds) { [weak self] in
                guard let self else { return }
                self.pendingCountdownPanel = nil
                self.beginScreenCaptureProcess(request)
            }
            pendingCountdownPanel = panel
            panel.start()
            return
        }

        beginScreenCaptureProcess(request)
    }

    private func cancelPendingCountdown() {
        pendingCountdownPanel?.teardown()
        pendingCountdownPanel = nil
        resetCaptureState()
    }

    private func beginScreenCaptureProcess(_ request: ScreenCaptureRequest) {
        // Record current clipboard state, then ask macOS screencapture to write
        // the selected/full-screen image to the clipboard.
        captureLastSeenChangeCount = NSPasteboard.general.changeCount

        guard let process = runScreenCapture(request) else {
            resetCaptureState()
            return
        }
        captureProcessID = process.processIdentifier
        viewModel?.updateCaptureStatus("Capture: screencapture running pid \(process.processIdentifier)")

        // Poll clipboard for the new screenshot
        let startTime = Date()
        clipboardPollTimer?.invalidate()
        clipboardPollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            _ = timer
            DispatchQueue.main.async { [weak self] in
                self?.pollClipboardForCapture(startTime: startTime)
            }
        }
    }

    private func pollClipboardForCapture(startTime: Date) {
        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount != captureLastSeenChangeCount, NSImage(pasteboard: pasteboard) != nil {
            resetCaptureState()
            handleClipboardCapture()
        } else if pasteboard.changeCount != captureLastSeenChangeCount {
            captureLastSeenChangeCount = pasteboard.changeCount
        } else if Date().timeIntervalSince(startTime) > 120 {
            // Timeout — user likely cancelled
            viewModel?.updateCaptureStatus("Capture: timed out or cancelled")
            resetCaptureState()
        }
    }

    private func runScreenCapture(_ request: ScreenCaptureRequest) -> Process? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = request.screencaptureArguments
        process.terminationHandler = { [weak self] finishedProcess in
            let processID = finishedProcess.processIdentifier
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.handleScreenCaptureProcessFinished(processID: processID)
            }
        }
        do {
            try process.run()
            return process
        } catch {
            NSSound.beep()
            viewModel?.updateCaptureStatus("Capture: failed to start screencapture")
            NSLog("ImageGrab: screencapture failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func handleScreenCaptureProcessFinished(processID: Int32) {
        guard captureProcessID == processID else { return }

        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount != captureLastSeenChangeCount, NSImage(pasteboard: pasteboard) != nil {
            resetCaptureState()
            handleClipboardCapture()
            return
        }

        // Interactive region capture exits without changing the clipboard when the user presses Esc.
        viewModel?.updateCaptureStatus("Capture: screencapture exited without image")
        resetCaptureState()
    }

    private func resetCaptureState() {
        clipboardPollTimer?.invalidate()
        clipboardPollTimer = nil
        isCaptureInProgress = false
        captureProcessID = nil
        pendingCountdownPanel?.teardown()
        pendingCountdownPanel = nil
    }

    private func handleClipboardCapture() {
        guard let image = NSImage(pasteboard: NSPasteboard.general) else {
            NSSound.beep()
            viewModel?.updateCaptureStatus("Capture: no image on clipboard")
            return
        }
        viewModel?.updateCaptureStatus("Capture: preview ready")

        let preview = CapturePreviewWindow(
            image: image,
            onSave: { [weak self] img, copyPath, baseName in
                self?.handleCapturedImage(img, copyPath: copyPath, baseName: baseName)
                self?.previewWindow = nil
            },
            onCancel: { [weak self] in
                self?.previewWindow = nil
            }
        )
        self.previewWindow = preview
        preview.show()
    }

    private func handleCapturedImage(_ image: NSImage, copyPath: Bool = false, baseName: String? = nil) {
        guard let entry = captureStore.addCapture(image: image, preferredBaseName: baseName) else {
            NSSound.beep()
            return
        }

        if copyPath {
            let path = captureStore.path(for: entry)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        }

        viewModel?.refresh()
        viewModel?.updateCaptureStatus("Capture: saved")

        // Show popover as feedback
        if let button = statusItem?.button, let popover, !popover.isShown {
            showPopover(relativeTo: button)
        }
    }
}
