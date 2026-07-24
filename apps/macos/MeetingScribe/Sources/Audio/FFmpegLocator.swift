import Foundation

/// Finds the `ffmpeg` binary at runtime.
///
/// ffmpeg merges the separate mic and system-audio tracks into the single file
/// whisper transcribes. When it is missing the merge silently degrades to
/// mic-only — the user keeps their own voice and loses everyone else's — so the
/// app needs to know whether it is actually available, not assume a path.
///
/// The previous hardcoded `/opt/homebrew/bin/ffmpeg` missed Intel Macs
/// (`/usr/local/bin`), MacPorts, and any custom install on `PATH`.
enum FFmpegLocator {

    /// Where Homebrew (arm64 and x86_64), MacPorts, and the system put binaries.
    /// A GUI app launched from Finder inherits a minimal `PATH`, so these
    /// explicit locations are checked before falling back to the environment.
    static let defaultSearchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/opt/local/bin",
        "/usr/bin",
    ]

    /// Resolve the ffmpeg binary, or `nil` when it is not installed.
    static func resolve(
        searchPaths: [String] = defaultSearchPaths,
        environmentPath: String? = ProcessInfo.processInfo.environment["PATH"]
    ) -> URL? {
        let pathEntries = (environmentPath?.split(separator: ":").map(String.init)) ?? []
        for directory in searchPaths + pathEntries {
            guard !directory.isEmpty else { continue }
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("ffmpeg")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Whether ffmpeg is installed — used by Settings → Setup to show status.
    static var isAvailable: Bool { resolve() != nil }
}
