import SwiftUI

struct RecentRecordingsList: View {
    let recordings: [Recording]

    var body: some View {
        if recordings.isEmpty {
            Text("No recent recordings")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(recordings.prefix(5)) { recording in
                HStack {
                    VStack(alignment: .leading) {
                        Text(recording.title)
                            .font(.caption)
                            .lineLimit(1)
                        Text(recording.date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }
}
