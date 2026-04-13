import Foundation

enum OllamaServerError: LocalizedError {
    case binaryNotFound
    case startFailed(String)
    case didNotBecomeHealthy

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Ollama is not installed. Install it from the Setup tab first."
        case .startFailed(let detail):
            return "Failed to start Ollama: \(detail)"
        case .didNotBecomeHealthy:
            return "Ollama started but is not responding on the configured endpoint."
        }
    }
}

/// Detects and starts the Ollama daemon. Does not manage its lifetime beyond
/// the initial launch — the daemon, once started, lives until killed or reboot.
struct OllamaServerManager {

    /// Resolve the ollama binary path, or nil if not installed.
    static func ollamaBinary() -> String? {
        let candidates = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Resolve the brew binary path (for `brew services`), or nil.
    static func brewBinary() -> String? {
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Start the Ollama daemon if it's not already running.
    /// Constructs an OllamaProvider internally to avoid Sendability issues with
    /// passing a class instance across async boundaries.
    /// Polls `OllamaProvider.isHealthy()` for up to `timeoutSeconds` seconds.
    ///
    /// - Returns: `true` if the server is healthy at return time.
    /// - Throws: `OllamaServerError` on installation or launch failure.
    static func startIfNeeded(
        endpoint: String,
        model: String,
        timeoutSeconds: Double = 8.0
    ) async throws -> Bool {
        let provider = OllamaProvider(endpoint: endpoint, model: model)

        // Fast path: already running
        if await provider.isHealthy() {
            return true
        }

        guard let ollama = ollamaBinary() else {
            throw OllamaServerError.binaryNotFound
        }

        // Try brew services first (persistent across reboots)
        if let brew = brewBinary() {
            _ = try? await runAndWait(launchPath: brew, arguments: ["services", "start", "ollama"])
            if await waitUntilHealthy(endpoint: endpoint, model: model, timeoutSeconds: 3.0) {
                return true
            }
        }

        // Fall back to session-only: detach `ollama serve` into the background.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ollama)
        proc.arguments = ["serve"]
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            throw OllamaServerError.startFailed(error.localizedDescription)
        }

        if await waitUntilHealthy(endpoint: endpoint, model: model, timeoutSeconds: timeoutSeconds) {
            return true
        }
        throw OllamaServerError.didNotBecomeHealthy
    }

    /// Poll a freshly constructed provider until it's healthy or the timeout elapses.
    private static func waitUntilHealthy(
        endpoint: String,
        model: String,
        timeoutSeconds: Double
    ) async -> Bool {
        let provider = OllamaProvider(endpoint: endpoint, model: model)
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await provider.isHealthy() {
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 s
        }
        return false
    }

    /// Run a command synchronously off the main actor and return the exit status.
    @discardableResult
    private static func runAndWait(launchPath: String, arguments: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int32, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: launchPath)
                proc.arguments = arguments
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = FileHandle.nullDevice
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    cont.resume(returning: proc.terminationStatus)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}
