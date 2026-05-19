import CoreGraphics
import Foundation

public struct CaptureRegion: Codable, Equatable, Sendable {
    public let screenFrame: CGRect
    public let rect: CGRect

    public init(screenFrame: CGRect, rect: CGRect) {
        self.screenFrame = screenFrame.standardized
        self.rect = rect.standardized
    }

    public var isUsable: Bool {
        rect.width >= 4 && rect.height >= 4
    }

    public var screencaptureRect: CGRect {
        CGRect(
            x: rect.minX,
            y: screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    public var screencaptureArgument: String {
        let captureRect = screencaptureRect.integral
        return "\(Int(captureRect.minX)),\(Int(captureRect.minY)),\(Int(captureRect.width)),\(Int(captureRect.height))"
    }
}
