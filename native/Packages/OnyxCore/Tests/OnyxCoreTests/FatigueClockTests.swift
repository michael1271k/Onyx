import Foundation
import Testing
@testable import OnyxCore

/// W10 — the card asks the question the time of day makes sense of.
///
/// No golden vector: the rule has no web original to export from. What is
/// pinned is the clock's behaviour on a fixed day — and that the stress
/// index's input (`dayMean`, every slot) does not move when the question does.
@Suite("Fatigue — the clock picks the question")
struct FatigueClockTests {

    @Test("07:00 on a training day asks before training; 19:00 asks after")
    func trainingDayByClock() {
        #expect(Fatigue.askingSlot(isTraining: true, clock: .today(minutes: 7 * 60)) == .pre)
        #expect(Fatigue.askingSlot(isTraining: true, clock: .today(minutes: 10 * 60 + 59)) == .pre)
        #expect(Fatigue.askingSlot(isTraining: true, clock: .today(minutes: 14 * 60)) == .pre)
        #expect(Fatigue.askingSlot(isTraining: true, clock: .today(minutes: 18 * 60 + 29)) == .pre)
        #expect(Fatigue.askingSlot(isTraining: true, clock: .today(minutes: 18 * 60 + 30)) == .post)
        #expect(Fatigue.askingSlot(isTraining: true, clock: .today(minutes: 19 * 60)) == .post)
    }

    @Test("a session finished at 14:00 flips the question at 14:00, not at 18:30")
    func sessionEndFlipsIt() {
        let ended = 14 * 60
        #expect(Fatigue.askingSlot(isTraining: true, clock: .today(minutes: 13 * 60 + 59), sessionEndedMinutes: ended) == .pre)
        #expect(Fatigue.askingSlot(isTraining: true, clock: .today(minutes: 14 * 60), sessionEndedMinutes: ended) == .post)
        #expect(Fatigue.askingSlot(isTraining: true, clock: .today(minutes: 16 * 60), sessionEndedMinutes: ended) == .post)
        // An early session is over early: 09:30 after a 09:00 finish is "after".
        #expect(Fatigue.askingSlot(isTraining: true, clock: .today(minutes: 9 * 60 + 30), sessionEndedMinutes: 9 * 60) == .post)
        // A session still running (no end yet) is "before" — it is asked mid-session.
        #expect(Fatigue.askingSlot(isTraining: true, clock: .today(minutes: 15 * 60), sessionEndedMinutes: nil) == .pre)
    }

    @Test("a rest day never asks the pre-session question")
    func restDayNeverAsksPre() {
        for minute in stride(from: 0, to: 24 * 60, by: 5) {
            for ended in [nil, 9 * 60, 14 * 60] as [Int?] {
                let slot = Fatigue.askingSlot(isTraining: false, clock: .today(minutes: minute), sessionEndedMinutes: ended)
                #expect(slot != .pre && slot != .post, "rest day asked \(slot) at \(minute)")
                #expect(Fatigue.restSlots.contains(slot))
            }
        }
        #expect(Fatigue.askingSlot(isTraining: false, clock: .today(minutes: 7 * 60)) == .waking)
        #expect(Fatigue.askingSlot(isTraining: false, clock: .today(minutes: 11 * 60)) == .midday)
        #expect(Fatigue.askingSlot(isTraining: false, clock: .today(minutes: 18 * 60 + 30)) == .night)
        #expect(Fatigue.askingSlot(isTraining: false, clock: .past) == .night)
    }

    @Test("a day that has happened asks its last slot; the answer is always one the day has")
    func pastDayAndVocabulary() {
        #expect(Fatigue.askingSlot(isTraining: true, clock: .past) == .post)
        #expect(Fatigue.askingSlot(isTraining: true, clock: .past, sessionEndedMinutes: 14 * 60) == .post)
        for isTraining in [true, false] {
            for minute in stride(from: 0, to: 24 * 60, by: 15) {
                let slot = Fatigue.askingSlot(isTraining: isTraining, clock: .today(minutes: minute))
                #expect(Fatigue.slotsForDay(isTraining: isTraining).contains(slot))
            }
        }
    }

    @Test("the day mean over two slots is unchanged by any of it — STRESS_MODEL §2")
    func dayMeanIsEverySlot() {
        let day: FatigueDay = [.pre: 2, .post: 4]
        #expect(Fatigue.dayMean(day) == 3)
        // The question moving does not move the input: the mean is a fold over
        // the day's slots and takes no clock.
        for minute in [7 * 60, 14 * 60, 19 * 60] {
            _ = Fatigue.askingSlot(isTraining: true, clock: .today(minutes: minute), sessionEndedMinutes: 14 * 60)
            #expect(Fatigue.dayMean(day) == 3)
        }
        #expect(Fatigue.dayMean([.waking: 1, .pre: 2, .post: 5]) == 8.0 / 3.0)
        #expect(Fatigue.latest(day)?.slot == .post)
    }

    @Test("the missing end is named only when exactly one end is logged")
    func deltaMissing() {
        #expect(Fatigue.deltaMissing([.waking: 2, .pre: 3]) == .post)
        #expect(Fatigue.deltaMissing([.post: 4]) == .pre)
        #expect(Fatigue.deltaMissing([.pre: 3, .post: 4]) == nil)
        #expect(Fatigue.delta([.pre: 3, .post: 4]) == 1)
        #expect(Fatigue.deltaMissing([.waking: 2]) == nil)
        #expect(Fatigue.deltaMissing([.waking: 2, .midday: 3, .night: 4]) == nil)
        #expect(Fatigue.deltaMissing([:]) == nil)
    }
}
