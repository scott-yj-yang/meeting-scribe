import Foundation
import AVFoundation
import Speech
import EventKit
import ScreenCaptureKit
import AppKit

enum PermissionKind: String, CaseIterable, Sendable {
    case microphone
    case speechRecognition
    case calendar
    case screenRecording

    var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .speechRecognition: return "Speech Recognition"
        case .calendar: return "Calendar"
        case .screenRecording: return "Screen & System Audio"
        }
    }

    var subtitle: String {
        switch self {
        case .microphone:
            return "Required. MeetingScribe records your microphone to capture the meeting audio."
        case .speechRecognition:
            return "Required for live transcript. Runs entirely on-device."
        case .calendar:
            return "Optional. Lets MeetingScribe suggest upcoming meetings to record."
        case .screenRecording:
            return "Optional. Enables capturing system audio (the other person's voice on video calls)."
        }
    }

    var isRequired: Bool {
        switch self {
        case .microphone: return true
        case .speechRecognition, .calendar, .screenRecording: return false
        }
    }

    var symbolName: String {
        switch self {
        case .microphone: return "mic.fill"
        case .speechRecognition: return "text.bubble.fill"
        case .calendar: return "calendar"
        case .screenRecording: return "rectangle.on.rectangle.square"
        }
    }
}

enum PermissionStatus: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case needsSystemSettings

    var displayText: String {
        switch self {
        case .notDetermined: return "Not requested"
        case .granted: return "Granted"
        case .denied: return "Denied"
        case .needsSystemSettings: return "Open System Settings"
        }
    }

    var isGranted: Bool {
        if case .granted = self { return true }
        return false
    }
}

@MainActor
final class PermissionsManager: ObservableObject {
    @Published private(set) var statuses: [PermissionKind: PermissionStatus] = [:]

    init() {
        Task { await refreshAll() }
    }

    /// Refresh cached status without prompting.
    func refreshAll() async {
        var next: [PermissionKind: PermissionStatus] = [:]
        next[.microphone] = currentMicrophoneStatus()
        next[.speechRecognition] = currentSpeechStatus()
        next[.calendar] = currentCalendarStatus()
        next[.screenRecording] = await currentScreenRecordingStatus()
        statuses = next
    }

    func request(_ kind: PermissionKind) async {
        switch kind {
        case .microphone:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            statuses[kind] = granted ? .granted : .denied
        case .speechRecognition:
            // Run on a background queue to avoid TCC/MainActor conflict (matches SpeechAuthHelper idiom).
            let status = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
                }
            }
            statuses[kind] = mapSpeech(status)
        case .calendar:
            do {
                let granted = try await EKEventStore().requestFullAccessToEvents()
                statuses[kind] = granted ? .granted : .denied
            } catch {
                statuses[kind] = .denied
            }
        case .screenRecording:
            // ScreenCaptureKit has no programmatic request API — deep-link
            // to System Settings and re-probe after the user acts.
            openSystemScreenRecordingSettings()
            try? await Task.sleep(nanoseconds: 500_000_000)
            statuses[kind] = await currentScreenRecordingStatus()
        }
    }

    // MARK: - Current Status Probes

    nonisolated func currentMicrophoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: return .notDetermined
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        @unknown default: return .notDetermined
        }
    }

    nonisolated func currentSpeechStatus() -> PermissionStatus {
        return mapSpeech(SFSpeechRecognizer.authorizationStatus())
    }

    nonisolated func currentCalendarStatus() -> PermissionStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .fullAccess, .authorized: return .granted
        case .writeOnly: return .granted
        case .denied, .restricted: return .denied
        @unknown default: return .notDetermined
        }
    }

    /// Screen recording can't be probed without trying `SCShareableContent.current`.
    /// Success = granted; failure = denied or not-yet-granted (indistinguishable).
    nonisolated func currentScreenRecordingStatus() async -> PermissionStatus {
        do {
            _ = try await SCShareableContent.current
            return .granted
        } catch {
            return .needsSystemSettings
        }
    }

    // MARK: - Helpers

    nonisolated func mapSpeech(_ status: SFSpeechRecognizerAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        @unknown default: return .notDetermined
        }
    }

    private func openSystemScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
