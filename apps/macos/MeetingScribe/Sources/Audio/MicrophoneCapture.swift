import AVFoundation
import CoreAudio

final class MicrophoneCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var isCapturing = false
    var onAudioBuffer: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?
    var preferredDeviceUID: String?

    func start() throws {
        if let uid = preferredDeviceUID {
            setInputDevice(uid: uid)
        }

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
    var format: AVAudioFormat? {
        isCapturing ? engine.inputNode.outputFormat(forBus: 0) : nil
    }

    private func setInputDevice(uid: String) {
        // Find all audio devices and match by UID
        var propSize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propSize)
        let deviceCount = Int(propSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propSize, &deviceIDs)

        for deviceID in deviceIDs {
            // Get device UID
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var deviceUID: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            let status = AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &deviceUID)

            if status == noErr && (deviceUID as String) == uid {
                // Set as default input
                var mutableDeviceID = deviceID
                var inputAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyDefaultInputDevice,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                AudioObjectSetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject),
                    &inputAddress, 0, nil,
                    UInt32(MemoryLayout<AudioDeviceID>.size),
                    &mutableDeviceID
                )
                return
            }
        }
    }
}
