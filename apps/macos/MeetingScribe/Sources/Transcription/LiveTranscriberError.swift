import Foundation

enum LiveTranscriberError: Error, LocalizedError {
    case whisperMissing
    case vadModelMissing
    case processFailed(String)
    case jsonParseFailed(String)

    var errorDescription: String? {
        switch self {
        case .whisperMissing:
            return "whisper-cli not found. Install via Settings → Setup."
        case .vadModelMissing:
            return "silero-vad.onnx not found alongside whisper. Live transcript falling back to non-VAD."
        case .processFailed(let stderr):
            return "whisper-cli failed: \(stderr)"
        case .jsonParseFailed(let detail):
            return "Failed to parse whisper output: \(detail)"
        }
    }
}
