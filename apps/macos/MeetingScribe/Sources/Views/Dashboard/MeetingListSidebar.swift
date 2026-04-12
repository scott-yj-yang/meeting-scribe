import SwiftUI

// MARK: - Embeddable content (no enclosing List)

struct MeetingListContent: View {
    let meetings: [LocalMeeting]
    var searchText: String = ""
    var selectedType: String? = nil
    var onDelete: ((LocalMeeting) -> Void)? = nil

    private var filtered: [LocalMeeting] {
        var result = meetings
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(q) ||
                ($0.transcriptSnippet?.lowercased().contains(q) == true)
            }
        }
        if let type = selectedType {
            result = result.filter { $0.meetingType?.lowercased() == type }
        }
        return result
    }

    private var grouped: [(String, [LocalMeeting])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: filtered) { meeting -> String in
            if cal.isDateInToday(meeting.date) { return "Today" }
            if cal.isDateInYesterday(meeting.date) { return "Yesterday" }
            return meeting.date.formatted(.dateTime.month(.wide).day().year())
        }
        return dict.sorted { lhs, rhs in
            guard let l = lhs.value.first?.date, let r = rhs.value.first?.date else { return false }
            return l > r
        }
    }

    var body: some View {
        ForEach(grouped, id: \.0) { group, meetings in
            Section(group) {
                ForEach(meetings) { meeting in
                    MeetingRow(meeting: meeting)
                        .tag(meeting)
                        .contextMenu {
                            Button(role: .destructive) {
                                onDelete?(meeting)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            if let dirURL = meeting.directoryURL {
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([dirURL])
                                } label: {
                                    Label("Show in Finder", systemImage: "folder")
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                onDelete?(meeting)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }
}

// MARK: - Standalone sidebar (backward compat)

struct MeetingListSidebar: View {
    let meetings: [LocalMeeting]
    @Binding var selection: LocalMeeting?
    @State private var searchText = ""
    @State private var selectedType: String?

    var body: some View {
        List(selection: $selection) {
            MeetingListContent(
                meetings: meetings,
                searchText: searchText,
                selectedType: selectedType
            )
        }
        .searchable(text: $searchText, prompt: "Search meetings")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("All") { selectedType = nil }
                    Divider()
                    ForEach(["1:1", "Subgroup", "Lab Meeting", "Standup", "Casual"], id: \.self) { type in
                        Button(type) { selectedType = type.lowercased() }
                    }
                } label: {
                    Image(systemName: selectedType != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
        }
    }
}

private struct MeetingRow: View {
    let meeting: LocalMeeting

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(meeting.title)
                .font(.system(.body, design: .rounded, weight: .medium))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(meeting.date.formatted(.dateTime.hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatDuration(meeting.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let type = meeting.meetingType {
                    Text(type)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .cornerRadius(3)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        if m == 0 { return "\(Int(seconds))s" }
        if m < 60 { return "\(m)m" }
        return "\(m / 60)h \(m % 60)m"
    }
}

extension LocalMeeting: Hashable {
    static func == (lhs: LocalMeeting, rhs: LocalMeeting) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
