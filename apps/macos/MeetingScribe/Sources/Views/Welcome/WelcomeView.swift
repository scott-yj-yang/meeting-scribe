import SwiftUI
import AppKit

struct WelcomeView: View {
    @StateObject private var permissions = PermissionsManager()
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            cards
            Divider()
            footer
        }
        .frame(width: 560, height: 600)
        .task {
            await permissions.refreshAll()
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.blue)
            Text("Welcome to MeetingScribe")
                .font(.system(.title, design: .rounded, weight: .semibold))
            Text("To record and transcribe meetings, MeetingScribe needs access to a few things. Everything runs on your Mac — no audio leaves the device.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var cards: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(PermissionKind.allCases, id: \.self) { kind in
                    PermissionCard(
                        kind: kind,
                        status: permissions.statuses[kind] ?? .notDetermined,
                        onGrant: {
                            Task { await permissions.request(kind) }
                        },
                        onOpenSettings: {
                            openSystemSettings(for: kind)
                        }
                    )
                }
            }
            .padding(20)
        }
    }

    private var footer: some View {
        HStack {
            Button("Skip for now") {
                hasCompletedWelcome = true
            }
            .buttonStyle(.borderless)

            Spacer()

            Button(allRequiredGranted ? "Get Started" : "Continue anyway") {
                hasCompletedWelcome = true
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var allRequiredGranted: Bool {
        PermissionKind.allCases
            .filter(\.isRequired)
            .allSatisfy { permissions.statuses[$0]?.isGranted == true }
    }

    private func openSystemSettings(for kind: PermissionKind) {
        let urlString: String
        switch kind {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .speechRecognition:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        case .calendar:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        case .screenRecording:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
