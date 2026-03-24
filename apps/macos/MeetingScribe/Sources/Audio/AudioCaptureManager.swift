import AVFoundation
import ScreenCaptureKit

@MainActor
class AudioCaptureManager: ObservableObject {
    private let micCapture = MicrophoneCapture()
    private let systemCapture = SystemAudioCapture()

    @Published var isCapturing = false

    var onMicAudio: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?
    var onSystemAudio: (@Sendable (CMSampleBuffer) -> Void)?

    func startCapture() async throws {
        let micHandler = onMicAudio
        micCapture.onAudioBuffer = { buffer, time in
            micHandler?(buffer, time)
        }
        try micCapture.start()

        let sysHandler = onSystemAudio
        systemCapture.onAudioBuffer = { sampleBuffer in
            sysHandler?(sampleBuffer)
        }
        try await systemCapture.start()

        isCapturing = true
    }

    func stopCapture() async {
        micCapture.stop()
        await systemCapture.stop()
        isCapturing = false
    }
}
