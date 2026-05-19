import Foundation

/// Delay applied between the capture trigger (popover button or global hotkey)
/// and the moment `screencapture` is actually invoked. Lets the user prepare
/// hover menus, tooltips, or dropdowns before the shot is taken.
public enum CaptureDelay: Int, CaseIterable, Identifiable, Codable, Sendable {
    case none = 0
    case seconds3 = 3
    case seconds5 = 5
    case seconds10 = 10

    public var id: Int { rawValue }
    public var seconds: Int { rawValue }

    public var label: String {
        switch self {
        case .none: return "Now"
        case .seconds3: return "3s"
        case .seconds5: return "5s"
        case .seconds10: return "10s"
        }
    }

    /// Verbose label used by accessibility and the countdown overlay.
    public var accessibilityLabel: String {
        switch self {
        case .none: return "No delay"
        case .seconds3: return "3 second delay"
        case .seconds5: return "5 second delay"
        case .seconds10: return "10 second delay"
        }
    }
}
