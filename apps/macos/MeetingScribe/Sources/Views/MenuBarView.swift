import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showSettings {
                // Inline settings
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Settings")
                            .font(.headline)
                        Spacer()
                        Button("Done") { showSettings = false }
                            .buttonStyle(.borderless)
                    }

                    Divider()

                    Text("Server URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("http://localhost:3000", text: $appState.serverURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    Text("Output Directory")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("~/MeetingScribe", text: $appState.outputDirectory)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    Toggle("Save raw audio files", isOn: $appState.saveAudio)
                        .font(.caption)
                }
            } else {
                // Main view
                if appState.isRecording {
                    RecordingIndicator(duration: appState.recordingDuration)

                    // Live transcription text
                    if !appState.transcriptionManager.liveText.isEmpty {
                        ScrollView {
                            Text(appState.transcriptionManager.liveText)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 80)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                    }

                    // Segment count
                    if !appState.transcriptionManager.segments.isEmpty {
                        Text("\(appState.transcriptionManager.segments.count) segments saved")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

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

                if let message = appState.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.lowercased().contains("fail") ? .red : .secondary)
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

                Button("Settings...") {
                    showSettings = true
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
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
