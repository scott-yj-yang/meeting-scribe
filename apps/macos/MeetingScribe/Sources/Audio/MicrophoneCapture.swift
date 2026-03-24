import AVFoundation

class MicrophoneCapture {
    private let engine = AVAudioEngine()
    private var isCapturing = false
    var onAudioBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?

    func start() throws {
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            self?.onAudioBuffer?(buffer, time)
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
