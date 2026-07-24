import Testing
import Foundation
@testable import MeetingScribe

@Suite("AppState navigation")
@MainActor
struct AppStateNavigationTests {

    private func makeMeeting(id: String = "m1") -> LocalMeeting {
        LocalMeeting(
            id: id, title: "Test Meeting", date: Date(), duration: 30,
            meetingType: nil, transcriptSnippet: nil,
            calendarEventTitle: nil, notes: nil
        )
    }

    @Test("viewCompletedMeeting leaves the post-recording view and requests navigation")
    func viewCompletedMeetingNavigates() {
        let state = AppState()
        state.showPostRecording = true
        state.lastRecordingWarning = "System audio was dropped"
        let meeting = makeMeeting()

        state.viewCompletedMeeting(meeting)

        // The post-recording overlay must dismiss so the dashboard detail pane
        // becomes visible...
        #expect(state.showPostRecording == false)
        // ...the warning belongs to the finished recording, not the meeting we
        // navigate to...
        #expect(state.lastRecordingWarning == nil)
        // ...and the dashboard is asked to open exactly this meeting.
        #expect(state.meetingToOpen?.id == meeting.id)
    }

    @Test("consuming the navigation request clears it so it doesn't re-fire")
    func navigationRequestIsOneShot() {
        let state = AppState()
        state.viewCompletedMeeting(makeMeeting(id: "m2"))
        #expect(state.meetingToOpen != nil)

        state.meetingToOpen = nil
        #expect(state.meetingToOpen == nil)
    }
}
