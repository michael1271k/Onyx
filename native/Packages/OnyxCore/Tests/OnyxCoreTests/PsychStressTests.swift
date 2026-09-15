import Foundation
import Testing
@testable import OnyxCore

@Suite("Psych stress — the slot is derived from the time")
struct PsychStressTests {

    @Test("forMinutes boundaries: noon starts midday, 18:00 starts evening")
    func forMinutesBoundaries() {
        #expect(StressSlot.forMinutes(719) == .morning)
        #expect(StressSlot.forMinutes(720) == .midday)
        #expect(StressSlot.forMinutes(1079) == .midday)
        #expect(StressSlot.forMinutes(1080) == .evening)
        #expect(StressSlot.forMinutes(0) == .morning)
        #expect(StressSlot.forMinutes(23 * 60 + 59) == .evening)
    }

    @Test("forClock goes through forMinutes, and a finished day files under evening")
    func forClock() {
        #expect(StressSlot.forClock(.today(minutes: 719)) == .morning)
        #expect(StressSlot.forClock(.today(minutes: 720)) == .midday)
        #expect(StressSlot.forClock(.today(minutes: 1080)) == .evening)
        #expect(StressSlot.forClock(.past) == .evening)
    }

    @Test("a slot's start is the minute the sort falls back to for a legacy row")
    func startMinutes() {
        #expect(StressSlot.morning.startMinutes == 0)
        #expect(StressSlot.midday.startMinutes == StressSlot.middayFromMinutes)
        #expect(StressSlot.evening.startMinutes == StressSlot.eveningFromMinutes)
    }
}
