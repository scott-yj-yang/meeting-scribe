import Testing
import Foundation
@testable import MeetingScribe

@Suite("TimestampFormatter")
struct TimestampFormatterTests {

    @Test("formats sub-minute durations as 0:ss")
    func formatsSubMinute() {
        #expect(TimestampFormatter.format(0) == "0:00")
        #expect(TimestampFormatter.format(7) == "0:07")
        #expect(TimestampFormatter.format(42) == "0:42")
    }

    @Test("formats sub-hour durations as m:ss")
    func formatsSubHour() {
        #expect(TimestampFormatter.format(60) == "1:00")
        #expect(TimestampFormatter.format(75) == "1:15")
        #expect(TimestampFormatter.format(599) == "9:59")
        #expect(TimestampFormatter.format(600) == "10:00")
    }

    @Test("formats hour+ durations as h:mm:ss")
    func formatsHours() {
        #expect(TimestampFormatter.format(3600) == "1:00:00")
        #expect(TimestampFormatter.format(3725) == "1:02:05")
        #expect(TimestampFormatter.format(3725.7) == "1:02:05") // truncates
    }

    @Test("clamps negative values to 0:00")
    func clampsNegative() {
        #expect(TimestampFormatter.format(-3) == "0:00")
    }
}
