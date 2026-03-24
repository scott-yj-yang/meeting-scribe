import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appState.isRecording {
                RecordingIndicator(duration: appState.recordingDuration)
                Button("Stop Recording") {
                    appState.toggleRecording()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button("Start Recording") {
                    appState.toggleRecording()
                }
                .buttonStyle(.borderedProminent)
            }

            // Status / error message
            if let message = appState.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(message.contains("failed") || message.contains("Failed") ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Recent")
                .font(.caption)
                .foregroundStyle(.secondary)
            RecentRecordingsList(recordings: appState.recentRecordings)

            Divider()

            SettingsLink {
                Text("Settings...")
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 280)
        .onAppear {
            appState.checkServerStatus()
        }
    }

    private var statusColor: Color {
        switch appState.serverStatus {
        case .connected: return .green
        case .disconnected: return .red
        case .unknown: return .yellow
        }
    }

    private var statusText: String {
        switch appState.serverStatus {
        case .connected: return "Server connected"
        case .disconnected: return "Server offline"
        case .unknown: return "Checking server..."
        }
    }
}
