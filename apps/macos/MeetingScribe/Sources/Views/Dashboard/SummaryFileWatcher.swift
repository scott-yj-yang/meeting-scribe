import Foundation

/// Watches a meeting directory for changes to `summary.md` and invokes a
/// callback on the main actor each time the file is written, replaced, or
/// deleted. Used so an external editor (Claude Code, VS Code) can write the
/// summary file and the panel picks it up live, without polling.
///
/// Watches the *directory* rather than the file itself because:
/// 1. summary.md may not exist yet when the user first opens the meeting.
/// 2. Editors typically write atomically by renaming a temp file over the
///    target — a per-file watch would lose its file descriptor on the rename.
///    Directory watches survive that and fire on the rename event.
@MainActor
final class SummaryFileWatcher {
    private let source: DispatchSourceFileSystemObject
    private let fd: Int32
    private var debounceTask: Task<Void, Never>?

    init?(directory: URL, onChange: @escaping @MainActor () -> Void) {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        self.fd = fd
        self.source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )
        self.source.setEventHandler { [weak self] in
            // Coalesce bursts of events (atomic writes can fire 2-3 times in
            // milliseconds) into a single reload ~150ms after the last event.
            self?.debounceTask?.cancel()
            self?.debounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                if Task.isCancelled { return }
                onChange()
            }
        }
        self.source.setCancelHandler { [fd] in
            close(fd)
        }
        self.source.resume()
    }

    deinit {
        source.cancel()
        debounceTask?.cancel()
    }
}
