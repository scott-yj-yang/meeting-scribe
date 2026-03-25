import Speech

/// Non-isolated helper to request speech recognition authorization
/// without triggering Swift 6 MainActor/TCC threading crashes.
enum SpeechAuthHelper {
    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            // Run on a background queue to avoid TCC/MainActor conflict
            DispatchQueue.global(qos: .userInitiated).async {
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        }
    }
}
