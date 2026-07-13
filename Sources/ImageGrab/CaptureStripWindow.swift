import AppKit
import SwiftUI

/// A borderless, non-activating panel that slides down from the top edge of a
/// screen to show the capture strip. Non-activating so showing it never steals
/// focus from the app the user is dragging captures into.
@MainActor
final class CaptureStripWindow: NSPanel {
    /// Invoked when the strip should close because the pointer left it.
    var onAutoHide: (() -> Void)?
    /// Returns true while a drag is in flight so auto-hide is suppressed.
    var isDragging: () -> Bool = { false }

    private(set) var isPresented = false
    private let stripHeight: CGFloat
    private let hideMargin: CGFloat = 10
    private var watchTimer: Timer?
    /// How long the pointer must stay off the strip before it auto-hides.
    private let hideGracePeriod: TimeInterval = 10
    /// When the pointer was first seen outside the strip; nil while inside.
    private var pointerExitedAt: Date?
    /// True while a tile is being renamed; suppresses pointer auto-hide so the
    /// strip doesn't vanish mid-edit if the cursor drifts off it.
    private var isEditingName = false

    init(viewModel: PopoverViewModel, height: CGFloat = 220, onClose: @escaping () -> Void) {
        self.stripHeight = height
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        animationBehavior = .none

        let host = NSHostingView(
            rootView: CaptureStripView(viewModel: viewModel, onClose: onClose) { [weak self] editing in
                self?.isEditingName = editing
            }
        )
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    // Allow SwiftUI controls to interact; combined with becomesKeyOnlyIfNeeded
    // the panel only takes key focus if a control actually needs it.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func present(on screen: NSScreen) {
        guard !isPresented else { return }
        isPresented = true

        let full = screen.frame
        let shown = NSRect(x: full.minX, y: full.maxY - stripHeight, width: full.width, height: stripHeight)
        let hidden = NSRect(x: full.minX, y: full.maxY, width: full.width, height: stripHeight)

        setFrame(hidden, display: false)
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(shown, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in self?.startWatching() }
        })
    }

    func dismiss() {
        guard isPresented else { return }
        isPresented = false
        stopWatching()

        let hidden = NSRect(x: frame.minX, y: frame.maxY, width: frame.width, height: frame.height)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().setFrame(hidden, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in self?.orderOut(nil) }
        })
    }

    // MARK: - Auto-hide

    private func startWatching() {
        guard watchTimer == nil else { return }
        watchTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.checkPointer()
            }
        }
    }

    private func stopWatching() {
        watchTimer?.invalidate()
        watchTimer = nil
        pointerExitedAt = nil
    }

    private func checkPointer() {
        guard isPresented, !isDragging(), !isEditingName else {
            pointerExitedAt = nil
            return
        }
        let point = NSEvent.mouseLocation
        if frame.insetBy(dx: -hideMargin, dy: -hideMargin).contains(point) {
            pointerExitedAt = nil
        } else if let exitedAt = pointerExitedAt {
            if Date().timeIntervalSince(exitedAt) >= hideGracePeriod {
                onAutoHide?()
            }
        } else {
            pointerExitedAt = Date()
        }
    }
}
