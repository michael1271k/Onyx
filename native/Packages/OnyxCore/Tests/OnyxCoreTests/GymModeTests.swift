import Testing
import Foundation
@testable import OnyxCore

@Suite("Gym mode — the window the store learns")
struct GymModeTests {

    @Test("fewer than eight starts is not a habit")
    func tooFewStarts() {
        #expect(GymMode.window(startMinutes: Array(repeating: 1080, count: 7)) == nil)
        #expect(GymMode.window(startMinutes: []) == nil)
    }

    @Test("the median, not the mean — one late night does not move the window")
    func medianNotMean() {
        // Eight 18:00 starts and one 23:40. The mean is 18:37; the median is
        // 18:00, and the window is the one the other eight sit in.
        let minutes = Array(repeating: 1080, count: 8) + [1420]
        let window = GymMode.window(startMinutes: minutes)
        #expect(window == 990...1170)
        #expect(GymMode.contains(1080, window: window!))
        #expect(!GymMode.contains(1420, window: window!))
    }

    @Test("an even count takes the lower middle, never the mean of two habits")
    func evenCount() {
        // Four 07:00 and four 19:00. The mean is 13:00, an hour never trained.
        let minutes = Array(repeating: 420, count: 4) + Array(repeating: 1140, count: 4)
        #expect(GymMode.window(startMinutes: minutes) == 330...510)
    }

    @Test("a window over midnight is matched on both sides of it")
    func wrapsMidnight() {
        let window = GymMode.window(startMinutes: Array(repeating: 1400, count: 8))!
        #expect(window == 1310...1490)
        #expect(GymMode.contains(1430, window: window))   // 23:50
        #expect(GymMode.contains(10, window: window))     // 00:10 the next day
        #expect(!GymMode.contains(720, window: window))   // noon
    }

    @Test("a start outside the day is not a start")
    func garbageIgnored() {
        let minutes = Array(repeating: 1080, count: 8) + [-5, 1440, 9999]
        #expect(GymMode.window(startMinutes: minutes) == 990...1170)
    }

    @Test("a live workout outranks the clock and the calendar")
    func liveWins() {
        #expect(GymMode.isDue(liveWorkout: true, sessionDueToday: false, minuteOfDay: 0, window: nil))
    }

    @Test("no session due, or no window, is no gym mode")
    func refusals() {
        let window = 990...1170
        #expect(!GymMode.isDue(liveWorkout: false, sessionDueToday: false, minuteOfDay: 1080, window: window))
        #expect(!GymMode.isDue(liveWorkout: false, sessionDueToday: true, minuteOfDay: 1080, window: nil))
        #expect(GymMode.isDue(liveWorkout: false, sessionDueToday: true, minuteOfDay: 1080, window: window))
    }
}
