import SwiftUI

struct PermissionCard: View {
    let kind: PermissionKind
    let status: PermissionStatus
    let onGrant: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: kind.symbolName)
                .font(.system(size: 22))
                .foregroundStyle(iconColor)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(kind.title)
                        .font(.system(.headline, design: .rounded))
                    if kind.isRequired {
                        Text("Required")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .foregroundStyle(.white)
                            .background(Color.orange, in: Capsule())
                    }
                    Spacer()
                    statusBadge
                }

                Text(kind.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    actionButton
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var iconColor: Color {
        switch status {
        case .granted: return .green
        case .denied, .needsSystemSettings: return .orange
        case .notDetermined: return .blue
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        Text(status.displayText)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(statusBadgeForeground)
            .background(statusBadgeBackground, in: Capsule())
    }

    private var statusBadgeForeground: Color {
        switch status {
        case .granted: return .green
        case .denied, .needsSystemSettings: return .orange
        case .notDetermined: return .secondary
        }
    }

    private var statusBadgeBackground: Color {
        switch status {
        case .granted: return Color.green.opacity(0.15)
        case .denied, .needsSystemSettings: return Color.orange.opacity(0.15)
        case .notDetermined: return Color.primary.opacity(0.08)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch status {
        case .notDetermined:
            Button("Grant Access", action: onGrant)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        case .granted:
            Label("Allowed", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
        case .denied:
            Button("Open System Settings", action: onOpenSettings)
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .needsSystemSettings:
            Button("Open System Settings", action: onOpenSettings)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}
