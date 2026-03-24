import AVFoundation
@preconcurrency import ScreenCaptureKit

@MainActor
class AudioCaptureManager: ObservableObject {
    private let micCapture = MicrophoneCapture()
    private let systemCapture = SystemAudioCapture()

    @Published var isCapturing = false
    @Published var captureMode: CaptureMode = .none
    var micFormat: AVAudioFormat? { micCapture.format }

    var onMicAudio: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?
    var onSystemAudio: (@Sendable (CMSampleBuffer) -> Void)?

    enum CaptureMode {
        case none
        case micOnly
        case micAndSystem
    }

    func startCapture() async {
        // Always start mic capture
        let micHandler = onMicAudio
        micCapture.onAudioBuffer = { buffer, time in
            micHandler?(buffer, time)
        }

        do {
            try micCapture.start()
        } catch {
            print("Mic capture failed: \(error)")
            return
        }

        // Try system audio — if it fails, continue with mic only
        let sysHandler = onSystemAudio
        systemCapture.onAudioBuffer = { sampleBuffer in
            sysHandler?(sampleBuffer)
        }

        do {
            try await systemCapture.start()
            captureMode = .micAndSystem
            print("Recording: microphone + system audio")
        } catch {
            captureMode = .micOnly
            print("System audio unavailable (\(error.localizedDescription)). Recording microphone only.")
        }

        isCapturing = true
    }

    func stopCapture() async {
        micCapture.stop()
        if captureMode == .micAndSystem {
            await systemCapture.stop()
        }
        isCapturing = false
        captureMode = .none
    }
}
