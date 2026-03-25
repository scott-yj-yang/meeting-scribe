import AVFoundation
@preconcurrency import ScreenCaptureKit

struct AudioDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let uid: String
}

@MainActor
class AudioCaptureManager: ObservableObject {
    private let micCapture = MicrophoneCapture()
    private let systemCapture = SystemAudioCapture()

    @Published var isCapturing = false
    @Published var captureMode: CaptureMode = .none
    @Published var availableMics: [AudioDevice] = []
    @Published var selectedMicID: String? = nil

    var micFormat: AVAudioFormat? { micCapture.format }

    var onMicAudio: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?
    var onSystemAudio: (@Sendable (CMSampleBuffer) -> Void)?

    enum CaptureMode {
        case none
        case micOnly
        case micAndSystem
    }

    func refreshMicList() {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices

        availableMics = devices.map { device in
            AudioDevice(id: device.uniqueID, name: device.localizedName, uid: device.uniqueID)
        }

        // Select default if none selected
        if selectedMicID == nil, let defaultDevice = AVCaptureDevice.default(for: .audio) {
            selectedMicID = defaultDevice.uniqueID
        }
    }

    func startCapture() async {
        // Set the selected mic as the preferred input device
        if let micID = selectedMicID {
            micCapture.preferredDeviceUID = micID
        }

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
