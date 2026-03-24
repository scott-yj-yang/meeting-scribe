@preconcurrency import ScreenCaptureKit
import AVFoundation

final class SystemAudioCapture: NSObject, @unchecked Sendable, SCStreamDelegate, SCStreamOutput {
    private var stream: SCStream?
    private var isCapturing = false
    var onAudioBuffer: (@Sendable (CMSampleBuffer) -> Void)?

    func start() async throws {
        // Run ScreenCaptureKit setup off the main actor
        let stream = try await Task.detached {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else {
                throw CaptureError.noDisplay
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])

            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            // Minimum 2x2 — some macOS versions reject 1x1
            config.width = 2
            config.height = 2

            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
            try await stream.startCapture()
            return stream
        }.value

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
        print("[SystemAudio] Stream stopped with error: \(error.localizedDescription)")
    }

    var isRunning: Bool { isCapturing }

    enum CaptureError: Error, LocalizedError {
        case noDisplay

        var errorDescription: String? {
            switch self {
            case .noDisplay: return "No display found"
            }
        }
    }
}
