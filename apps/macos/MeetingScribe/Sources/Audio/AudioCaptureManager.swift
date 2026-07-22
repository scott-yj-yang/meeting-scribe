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

    enum CaptureError: LocalizedError {
        case microphoneUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .microphoneUnavailable(let reason):
                return "Couldn't start the microphone (\(reason)). Check that no other app is using it, and that Microphone access is granted in System Settings → Privacy & Security."
            }
        }
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

    /// Start capturing. The microphone is required — if it fails to open this
    /// throws rather than returning quietly, so the caller never enters the
    /// recording state believing audio is being captured when it isn't.
    /// System audio stays best-effort.
    func startCapture() async throws {
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
            throw CaptureError.microphoneUnavailable(error.localizedDescription)
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
