import SwiftUI
import AppKit

/// Adds a pointing-hand cursor and a subtle hover background highlight.
/// Use on any clickable element that doesn't already get one from `.buttonStyle(.bordered)`.
struct ClickableHoverModifier: ViewModifier {
    var cornerRadius: CGFloat = 6
    var highlightOpacity: Double = 0.08
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? highlightOpacity : 0))
            )
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

/// Enforces a minimum hit target for icon-only controls. Defaults to 28x28 (comfortable
/// for a toolbar symbol). Pass `.large` for primary actions that need 44x44.
struct IconHitTargetModifier: ViewModifier {
    enum Size {
        case compact   // 28x28
        case standard  // 32x32
        case large     // 44x44

        var dimension: CGFloat {
            switch self {
            case .compact: return 28
            case .standard: return 32
            case .large: return 44
            }
        }
    }

    let size: Size

    func body(content: Content) -> some View {
        content
            .frame(minWidth: size.dimension, minHeight: size.dimension)
            .contentShape(Rectangle())
    }
}

extension View {
    /// Apply a hover background + pointing-hand cursor.
    func clickableHover(cornerRadius: CGFloat = 6, highlightOpacity: Double = 0.08) -> some View {
        modifier(ClickableHoverModifier(cornerRadius: cornerRadius, highlightOpacity: highlightOpacity))
    }

    /// Enforce a comfortable hit target on an icon-only control.
    func iconHitTarget(_ size: IconHitTargetModifier.Size = .compact) -> some View {
        modifier(IconHitTargetModifier(size: size))
    }
}
