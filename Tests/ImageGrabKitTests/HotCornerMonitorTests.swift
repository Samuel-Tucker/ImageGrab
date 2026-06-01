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
