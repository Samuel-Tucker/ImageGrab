import AppKit

/// Pure geometry: decides whether a screen-space point sits inside the hot
/// corner of one of the supplied screen frames. Kept free of AppKit state so it
/// can be unit-tested without real screens or events.
struct HotCornerDetector {
    enum Corner {
        case topRight
        case topLeft
        case topCenter
        /// A wide band hugging the top-right of the screen (`bandWidth` × `zoneSize`),
        /// matching the menu bar's system status-icon area.
        case topRightBand
    }

    var corner: Corner
    var zoneSize: CGFloat
    var bandWidth: CGFloat

    init(corner: Corner = .topRight, zoneSize: CGFloat = 6, bandWidth: CGFloat = 240) {
        self.corner = corner
        self.zoneSize = zoneSize
        self.bandWidth = bandWidth
    }

    /// The small activation rectangle at the chosen corner of a screen.
    /// Screen coordinates are bottom-left origin with y increasing upward, so
    /// the top of the screen is `frame.maxY`.
    func cornerZone(for frame: CGRect) -> CGRect {
        let y = frame.maxY - zoneSize
        switch corner {
        case .topRight:
            return CGRect(x: frame.maxX - zoneSize, y: y, width: zoneSize, height: zoneSize)
        case .topLeft:
            return CGRect(x: frame.minX, y: y, width: zoneSize, height: zoneSize)
        case .topCenter:
            let width = min(bandWidth, frame.width)
            return CGRect(x: frame.midX - width / 2, y: y, width: width, height: zoneSize)
        case .topRightBand:
            let width = min(bandWidth, frame.width)
            return CGRect(x: frame.maxX - width, y: y, width: width, height: zoneSize)
        }
    }

    /// Whether `point` is inside the hot corner of `frame`.
    ///
    /// The comparison is inclusive of the screen's outer edges. This matters
    /// because the cursor rests exactly at `frame.maxY` (and near `frame.maxX`)
    /// when slammed into the corner, and `CGRect.contains` treats those max edges
    /// as exclusive — which would silently miss the most common case.
    func contains(_ point: CGPoint, in frame: CGRect) -> Bool {
        let nearTop = point.y >= frame.maxY - zoneSize && point.y <= frame.maxY
        switch corner {
        case .topRight:
            let nearRight = point.x >= frame.maxX - zoneSize && point.x <= frame.maxX
            return nearTop && nearRight
        case .topLeft:
            let nearLeft = point.x >= frame.minX && point.x <= frame.minX + zoneSize
            return nearTop && nearLeft
        case .topCenter:
            let halfWidth = min(bandWidth, frame.width) / 2
            let nearCenter = point.x >= frame.midX - halfWidth && point.x <= frame.midX + halfWidth
            return nearTop && nearCenter
        case .topRightBand:
            let width = min(bandWidth, frame.width)
            let nearRight = point.x >= frame.maxX - width && point.x <= frame.maxX
            return nearTop && nearRight
        }
    }

    /// Index of the first screen whose hot corner contains `point`, or nil.
    func screenIndex(containing point: CGPoint, screenFrames: [CGRect]) -> Int? {
        for (index, frame) in screenFrames.enumerated() where contains(point, in: frame) {
            return index
        }
        return nil
    }
}

/// Tracks how long the cursor has continuously been in the hot corner and fires
/// exactly once when the dwell threshold elapses. Resets when the cursor leaves.
struct HotCornerDwellTracker {
    var dwell: TimeInterval

    private var enteredAt: TimeInterval?
    private var didFire = false

    init(dwell: TimeInterval = 0.2) {
        self.dwell = dwell
    }

    /// Feed the current in-zone state and time. Returns true on the single update
    /// where the dwell first completes while continuously in the zone.
    mutating func update(inZone: Bool, now: TimeInterval) -> Bool {
        guard inZone else {
            enteredAt = nil
            didFire = false
            return false
        }
        let start = enteredAt ?? now
        enteredAt = start
        if !didFire, now - start >= dwell {
            didFire = true
            return true
        }
        return false
    }
}

/// Watches the global cursor position and fires `onTrigger` when the user parks
/// the pointer in a screen's hot corner long enough. Polls `NSEvent.mouseLocation`
/// (which needs no special permission) on a timer so it works even while the
/// cursor is held still against the edge.
@MainActor
final class HotCornerMonitor {
    var onTrigger: ((NSScreen) -> Void)?
    /// Gate consulted before triggering (e.g. suppress while the strip is open).
    var isEnabled: () -> Bool = { true }

    private let detector: HotCornerDetector
    private var dwell: HotCornerDwellTracker
    private let pollInterval: TimeInterval
    private let screenFilter: (NSScreen) -> Bool
    private var timer: Timer?

    init(
        corner: HotCornerDetector.Corner = .topRight,
        zoneSize: CGFloat = 6,
        bandWidth: CGFloat = 240,
        dwell: TimeInterval = 0.2,
        pollInterval: TimeInterval = 0.05,
        screenFilter: @escaping (NSScreen) -> Bool = { _ in true }
    ) {
        self.detector = HotCornerDetector(
            corner: corner,
            zoneSize: zoneSize,
            bandWidth: bandWidth
        )
        self.dwell = HotCornerDwellTracker(dwell: dwell)
        self.pollInterval = pollInterval
        self.screenFilter = screenFilter
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.tick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let screens = NSScreen.screens.filter(screenFilter)
        guard !screens.isEmpty else { return }

        let enabled = isEnabled()
        let point = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        let frames = screens.map(\.frame)
        let index = enabled
            ? detector.screenIndex(containing: point, screenFrames: frames)
            : nil
        let inZone = index != nil

        if dwell.update(inZone: inZone, now: now), let index {
            onTrigger?(screens[index])
        }
    }
}
