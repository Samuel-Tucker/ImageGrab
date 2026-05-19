import CoreGraphics
import XCTest
@testable import ImageGrabKit

final class CaptureRegionTests: XCTestCase {
    func testScreencaptureArgumentConvertsAppKitYToTopLeftY() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let region = CaptureRegion(
            screenFrame: screen,
            rect: CGRect(x: 120, y: 300, width: 400, height: 250)
        )

        XCTAssertEqual(region.screencaptureArgument, "120,350,400,250")
    }

    func testScreencaptureArgumentHandlesNonZeroScreenOrigin() {
        let screen = CGRect(x: -1280, y: 0, width: 1280, height: 720)
        let region = CaptureRegion(
            screenFrame: screen,
            rect: CGRect(x: -1200, y: 100, width: 320, height: 240)
        )

        XCTAssertEqual(region.screencaptureArgument, "-1200,380,320,240")
    }

    func testTinyRegionsAreNotUsable() {
        let screen = CGRect(x: 0, y: 0, width: 100, height: 100)

        XCTAssertFalse(CaptureRegion(screenFrame: screen, rect: CGRect(x: 1, y: 1, width: 3, height: 10)).isUsable)
        XCTAssertFalse(CaptureRegion(screenFrame: screen, rect: CGRect(x: 1, y: 1, width: 10, height: 3)).isUsable)
        XCTAssertTrue(CaptureRegion(screenFrame: screen, rect: CGRect(x: 1, y: 1, width: 4, height: 4)).isUsable)
    }
}
