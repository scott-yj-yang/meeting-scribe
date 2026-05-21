import SwiftUI

/// Centralized animation timing for MeetingScribe so the whole app feels
/// coherent — same easing/duration vocabulary everywhere.
enum AppAnim {
    /// Fast button feedback (hover, tap). 130 ms.
    static let snappy = Animation.easeInOut(duration: 0.13)
    /// Standard control change (toggle, picker). Spring with subtle bounce.
    static let standard = Animation.spring(response: 0.32, dampingFraction: 0.78)
    /// View transitions (sheets, panels swapping). Smooth but not slow.
    static let viewTransition = Animation.spring(response: 0.45, dampingFraction: 0.85)
    /// Subtle pulses / breathing on idle indicators (recording dot, listening). 1.6 s.
    static let breathe = Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: true)
    /// Smooth value-driven animations (audio meters, progress bars). 80 ms linear.
    static let levelMeter = Animation.linear(duration: 0.08)
}
