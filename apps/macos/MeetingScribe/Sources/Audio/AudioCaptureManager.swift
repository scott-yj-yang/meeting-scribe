import AVFoundation
import ScreenCaptureKit

class AudioCaptureManager: ObservableObject {
    private let micCapture = MicrophoneCapture()
    private let systemCapture = SystemAudioCapture()

    @Published var isCapturing = false

    var onMicAudio: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?
    var onSystemAudio: ((CMSampleBuffer) -> Void)?

    func startCapture() async throws {
        micCapture.onAudioBuffer = { [weak self] buffer, time in
            self?.onMicAudio?(buffer, time)
        }
        try micCapture.start()

        systemCapture.onAudioBuffer = { [weak self] sampleBuffer in
            self?.onSystemAudio?(sampleBuffer)
        }
        try await systemCapture.start()

        await MainActor.run {
            isCapturing = true
        }
    }

    func stopCapture() async {
        micCapture.stop()
        await systemCapture.stop()

        await MainActor.run {
            isCapturing = false
        }
    }
}
