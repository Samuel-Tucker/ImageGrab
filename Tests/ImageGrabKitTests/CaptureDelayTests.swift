import CoreGraphics
import XCTest
@testable import ImageGrabKit

final class CaptureDelayTests: XCTestCase {
    func testRawValuesAreSeconds() {
        XCTAssertEqual(CaptureDelay.none.seconds, 0)
        XCTAssertEqual(CaptureDelay.seconds3.seconds, 3)
        XCTAssertEqual(CaptureDelay.seconds5.seconds, 5)
        XCTAssertEqual(CaptureDelay.seconds10.seconds, 10)
    }

    func testLabelsAreUserVisible() {
        XCTAssertEqual(CaptureDelay.none.label, "Now")
        XCTAssertEqual(CaptureDelay.seconds3.label, "3s")
        XCTAssertEqual(CaptureDelay.seconds5.label, "5s")
        XCTAssertEqual(CaptureDelay.seconds10.label, "10s")
    }

    func testAllCasesOrderedAscending() {
        XCTAssertEqual(CaptureDelay.allCases, [.none, .seconds3, .seconds5, .seconds10])
    }

    func testIdentifierMatchesSeconds() {
        for delay in CaptureDelay.allCases {
            XCTAssertEqual(delay.id, delay.seconds)
        }
    }

    func testCodableRoundTrip() throws {
        let payload = try JSONEncoder().encode(CaptureDelay.seconds5)
        let decoded = try JSONDecoder().decode(CaptureDelay.self, from: payload)
        XCTAssertEqual(decoded, .seconds5)
    }
}

@MainActor
final class PopoverViewModelCaptureDelayTests: XCTestCase {
    func testDefaultDelayIsNone() {
        let viewModel = PopoverViewModel(store: CaptureStore(capturesDirectory: scratchDirectory()))
        XCTAssertEqual(viewModel.captureDelay, .none)
    }

    func testCaptureDelayIsMutable() {
        let viewModel = PopoverViewModel(store: CaptureStore(capturesDirectory: scratchDirectory()))
        viewModel.captureDelay = .seconds5
        XCTAssertEqual(viewModel.captureDelay, .seconds5)
    }

    func testRepeatLastRegionRequiresUsableRegion() {
        let viewModel = PopoverViewModel(store: CaptureStore(capturesDirectory: scratchDirectory()))
        XCTAssertFalse(viewModel.canRepeatLastRegion)

        viewModel.lastCaptureRegion = CaptureRegion(
            screenFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            rect: CGRect(x: 1, y: 1, width: 20, height: 20)
        )

        XCTAssertTrue(viewModel.canRepeatLastRegion)
    }

    func testRepeatLastRegionInvokesCallbackWhenAvailable() {
        let viewModel = PopoverViewModel(store: CaptureStore(capturesDirectory: scratchDirectory()))
        viewModel.lastCaptureRegion = CaptureRegion(
            screenFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            rect: CGRect(x: 1, y: 1, width: 20, height: 20)
        )

        var didRepeat = false
        viewModel.onRepeatLastRegion = {
            didRepeat = true
        }

        viewModel.repeatLastRegion()

        XCTAssertTrue(didRepeat)
    }

    private func scratchDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageGrabTests-CaptureDelay-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
