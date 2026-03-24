import AVFoundation

final class MicrophoneCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var isCapturing = false
    var onAudioBuffer: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?

    func start() throws {
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let handler = onAudioBuffer
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
            handler?(buffer, time)
        }

        engine.prepare()
        try engine.start()
        isCapturing = true
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
    }

    var isRunning: Bool { isCapturing }
}
