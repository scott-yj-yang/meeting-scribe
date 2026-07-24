import Testing
@testable import MeetingScribe

@Suite("ZoomDetector")
struct ZoomDetectorTests {

    @Test("a Zoom meeting window counts as in-meeting")
    func meetingWindow() {
        #expect(ZoomDetector.isInMeeting(windows: [
            WindowInfo(ownerName: "zoom.us", title: "Zoom Meeting")
        ]))
    }

    @Test("the idle Zoom main window does not count")
    func idleWindow() {
        #expect(!ZoomDetector.isInMeeting(windows: [
            WindowInfo(ownerName: "zoom.us", title: "Zoom Workplace")
        ]))
        #expect(!ZoomDetector.isInMeeting(windows: [
            WindowInfo(ownerName: "zoom.us", title: "Zoom")
        ]))
    }

    @Test("a browser tab named like a meeting does not count")
    func browserTab() {
        #expect(!ZoomDetector.isInMeeting(windows: [
            WindowInfo(ownerName: "Safari", title: "Zoom Meeting - Join")
        ]))
    }

    @Test("no windows means not in a meeting")
    func noWindows() {
        #expect(!ZoomDetector.isInMeeting(windows: []))
    }
}
