import Testing
import Foundation
import Speech
@testable import MeetingScribe

@Suite("PermissionsManager")
struct PermissionsManagerTests {

    @Test("maps SFSpeechRecognizerAuthorizationStatus correctly")
    @MainActor
    func mapsSpeechStatus() {
        let manager = PermissionsManager()

        #expect(manager.mapSpeech(.notDetermined) == .notDetermined)
        #expect(manager.mapSpeech(.authorized) == .granted)
        #expect(manager.mapSpeech(.denied) == .denied)
        #expect(manager.mapSpeech(.restricted) == .denied)
    }

    @Test("PermissionKind.isRequired flags microphone only")
    func requiredPermissionIsMicrophoneOnly() {
        #expect(PermissionKind.microphone.isRequired == true)
        #expect(PermissionKind.speechRecognition.isRequired == false)
        #expect(PermissionKind.calendar.isRequired == false)
        #expect(PermissionKind.screenRecording.isRequired == false)
    }

    @Test("PermissionStatus.isGranted is true only for granted")
    func isGrantedMatchesGranted() {
        #expect(PermissionStatus.granted.isGranted == true)
        #expect(PermissionStatus.notDetermined.isGranted == false)
        #expect(PermissionStatus.denied.isGranted == false)
        #expect(PermissionStatus.needsSystemSettings.isGranted == false)
    }

    @Test("PermissionStatus display text is user-friendly")
    func statusDisplayText() {
        #expect(PermissionStatus.granted.displayText == "Granted")
        #expect(PermissionStatus.denied.displayText == "Denied")
        #expect(PermissionStatus.notDetermined.displayText == "Not requested")
    }
}
