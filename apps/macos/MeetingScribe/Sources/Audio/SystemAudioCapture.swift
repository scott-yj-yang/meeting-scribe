import ScreenCaptureKit
import AVFoundation

final class SystemAudioCapture: NSObject, @unchecked Sendable, SCStreamDelegate, SCStreamOutput {
    private var stream: SCStream?
    private var isCapturing = false
    var onAudioBuffer: (@Sendable (CMSampleBuffer) -> Void)?

    func start() async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.width = 1
        config.height = 1

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream.startCapture()

        self.stream = stream
        isCapturing = true
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
        isCapturing = false
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        onAudioBuffer?(sampleBuffer)
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Handle stream error
    }

    var isRunning: Bool { isCapturing }

    enum CaptureError: Error {
        case noDisplay
    }
}
