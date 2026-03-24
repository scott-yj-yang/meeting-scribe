import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Server") {
                TextField("Server URL", text: $appState.serverURL)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Output") {
                TextField("Output Directory", text: $appState.outputDirectory)
                    .textFieldStyle(.roundedBorder)
                Toggle("Save raw audio files", isOn: $appState.saveAudio)
            }
        }
        .padding()
        .frame(width: 400, height: 250)
    }
}
