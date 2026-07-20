import XCTest
@testable import ImageGrabKit

final class HotCornerMonitorTests: XCTestCase {

    // MARK: - HotCornerDetector

    func testTopRightCornerZoneContainsCornerPoint() {
        let detector = HotCornerDetector(corner: .topRight, zoneSize: 6)
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

        // Cursor slammed into the top-right corner (clamped a pixel inside).
        XCTAssertEqual(detector.screenIndex(containing: CGPoint(x: 999, y: 799), screenFrames: [screen]), 0)
        XCTAssertEqual(detector.screenIndex(containing: CGPoint(x: 995, y: 795), screenFrames: [screen]), 0)
    }

    func testCornerIsDetectedWhenCursorRestsExactlyOnTopRightEdge() {
        // Regression: the cursor pins at exactly (≈maxX, maxY) when slammed into
        // the corner. Detection must include those outer edges, not exclude them.
        let detector = HotCornerDetector(corner: .topRight, zoneSize: 6)
        let screen = CGRect(x: 0, y: 0, width: 3200, height: 1350)

        XCTAssertEqual(detector.screenIndex(containing: CGPoint(x: 3200, y: 1350), screenFrames: [screen]), 0)
        XCTAssertEqual(detector.screenIndex(containing: CGPoint(x: 3199.98, y: 1350.0), screenFrames: [screen]), 0)
    }

    func testPointsOutsideTopRightZoneDoNotMatch() {
        let detector = HotCornerDetector(corner: .topRight, zoneSize: 6)
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

        XCTAssertNil(detector.screenIndex(containing: CGPoint(x: 500, y: 400), screenFrames: [screen]))
        // Right edge but not near the top.
        XCTAssertNil(detector.screenIndex(containing: CGPoint(x: 999, y: 700), screenFrames: [screen]))
        // Top edge but not near the right.
        XCTAssertNil(detector.screenIndex(containing: CGPoint(x: 500, y: 799), screenFrames: [screen]))
    }

    func testTopLeftCornerZone() {
        let detector = HotCornerDetector(corner: .topLeft, zoneSize: 6)
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

        XCTAssertEqual(detector.screenIndex(containing: CGPoint(x: 1, y: 799), screenFrames: [screen]), 0)
        XCTAssertNil(detector.screenIndex(containing: CGPoint(x: 999, y: 799), screenFrames: [screen]))
    }

    func testTopCenterZoneMatchesWideTargetAtTopEdge() {
        let detector = HotCornerDetector(corner: .topCenter, zoneSize: 6, bandWidth: 440)
        let screen = CGRect(x: 0, y: 0, width: 3840, height: 1620)

        XCTAssertEqual(detector.cornerZone(for: screen), CGRect(x: 1700, y: 1614, width: 440, height: 6))
        XCTAssertTrue(detector.contains(CGPoint(x: 1920, y: 1620), in: screen))
        XCTAssertTrue(detector.contains(CGPoint(x: 1700, y: 1616), in: screen))
        XCTAssertFalse(detector.contains(CGPoint(x: 1699, y: 1616), in: screen))
        XCTAssertFalse(detector.contains(CGPoint(x: 1920, y: 1613), in: screen))
    }

    func testTopCenterZoneUsesOnlyMatchingScreenCoordinates() {
        let detector = HotCornerDetector(corner: .topCenter, zoneSize: 6, bandWidth: 240)
        let dell = CGRect(x: 0, y: 0, width: 2048, height: 864)

        XCTAssertEqual(
            detector.screenIndex(containing: CGPoint(x: 1024, y: 864), screenFrames: [dell]),
            0
        )
        XCTAssertNil(
            detector.screenIndex(containing: CGPoint(x: 3000, y: 900), screenFrames: [dell])
        )
    }

    func testTopRightBandMatchesWideTargetAnchoredAtRightEdge() {
        let detector = HotCornerDetector(corner: .topRightBand, zoneSize: 6, bandWidth: 440)
        let screen = CGRect(x: 0, y: 0, width: 3840, height: 1620)

        XCTAssertEqual(detector.cornerZone(for: screen), CGRect(x: 3400, y: 1614, width: 440, height: 6))
        // Cursor pinned at the very top-right corner.
        XCTAssertTrue(detector.contains(CGPoint(x: 3840, y: 1620), in: screen))
        // Anywhere along the band at the top edge.
        XCTAssertTrue(detector.contains(CGPoint(x: 3400, y: 1616), in: screen))
        // Just left of the band, or below it, must not match.
        XCTAssertFalse(detector.contains(CGPoint(x: 3399, y: 1616), in: screen))
        XCTAssertFalse(detector.contains(CGPoint(x: 3600, y: 1613), in: screen))
        // Top centre — where macOS drag-to-top gestures happen — stays free.
        XCTAssertFalse(detector.contains(CGPoint(x: 1920, y: 1620), in: screen))
    }

    func testTopRightBandOnOffsetScreenUsesThatScreensEdges() {
        let detector = HotCornerDetector(corner: .topRightBand, zoneSize: 6, bandWidth: 300)
        // Dell sits to the right of another display in global coordinates.
        let dell = CGRect(x: 1512, y: 0, width: 3840, height: 1620)

        XCTAssertEqual(
            detector.screenIndex(containing: CGPoint(x: 5352, y: 1620), screenFrames: [dell]),
            0
        )
        XCTAssertNil(
            detector.screenIndex(containing: CGPoint(x: 5000, y: 1620), screenFrames: [dell])
        )
    }

    func testMultiScreenReturnsCorrectIndex() {
        let detector = HotCornerDetector(corner: .topRight, zoneSize: 6)
        // Second display sits to the right; coordinates continue past the first.
        let screens = [
            CGRect(x: 0, y: 0, width: 1000, height: 800),
            CGRect(x: 1000, y: 0, width: 1440, height: 900)
        ]
        // Top-right of the second screen.
        XCTAssertEqual(detector.screenIndex(containing: CGPoint(x: 2439, y: 899), screenFrames: screens), 1)
        // Top-right of the first screen.
        XCTAssertEqual(detector.screenIndex(containing: CGPoint(x: 999, y: 799), screenFrames: screens), 0)
    }

    // MARK: - HotCornerDwellTracker

    func testDwellFiresOnceAfterThreshold() {
        var tracker = HotCornerDwellTracker(dwell: 0.2)

        XCTAssertFalse(tracker.update(inZone: true, now: 0.00))
        XCTAssertFalse(tracker.update(inZone: true, now: 0.10))
        XCTAssertTrue(tracker.update(inZone: true, now: 0.20))   // dwell elapsed
        XCTAssertFalse(tracker.update(inZone: true, now: 0.25))  // already fired, stays in zone
        XCTAssertFalse(tracker.update(inZone: true, now: 1.00))
    }

    func testDwellResetsWhenLeavingZone() {
        var tracker = HotCornerDwellTracker(dwell: 0.2)

        XCTAssertFalse(tracker.update(inZone: true, now: 0.0))
        XCTAssertTrue(tracker.update(inZone: true, now: 0.2))
        // Leave the zone, then return — must dwell again before firing.
        XCTAssertFalse(tracker.update(inZone: false, now: 0.3))
        XCTAssertFalse(tracker.update(inZone: true, now: 0.35))
        XCTAssertFalse(tracker.update(inZone: true, now: 0.50))
        XCTAssertTrue(tracker.update(inZone: true, now: 0.55))
    }

    func testNeverFiresWhileOutsideZone() {
        var tracker = HotCornerDwellTracker(dwell: 0.2)
        for step in 0...10 {
            XCTAssertFalse(tracker.update(inZone: false, now: Double(step) * 0.1))
        }
    }
}
