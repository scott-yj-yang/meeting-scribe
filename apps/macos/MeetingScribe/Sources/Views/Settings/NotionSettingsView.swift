import SwiftUI

struct NotionSettingsView: View {
    @StateObject private var settings = NotionSettings()
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        Form {
            Section("Notion integration") {
                Text("Create an internal integration at https://www.notion.so/my-integrations and paste the secret below. Share your target database with the integration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SecureField("Integration token (secret_…)", text: $settings.token)
                    .textFieldStyle(.roundedBorder)

                TextField("Database ID", text: $settings.databaseId)
                    .textFieldStyle(.roundedBorder)
                    .help("Copy the 32-character ID from the database URL")

                HStack {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        if testing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Test connection")
                        }
                    }
                    .disabled(settings.token.isEmpty || settings.databaseId.isEmpty || testing)

                    Spacer()

                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(result.hasPrefix("Connected") ? .green : .red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 500, minHeight: 350)
    }

    private func testConnection() async {
        testing = true
        defer { testing = false }
        let client = NotionClient(token: settings.token)
        do {
            let info = try await client.retrieveDatabase(id: settings.databaseId)
            testResult = "Connected — \"\(info.title)\""
        } catch {
            testResult = "Error: \(error.localizedDescription)"
        }
    }
}
