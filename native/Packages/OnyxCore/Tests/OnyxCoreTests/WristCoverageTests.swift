import Foundation
import Testing
@testable import OnyxCore

/// App Store W6 — missing must never read as zero.
@Suite("Wrist coverage")
struct WristCoverageTests {

    let from = Date(timeIntervalSince1970: 1_800_000_000)
    var to: Date { from.addingTimeInterval(12 * 3600) }

    /// A reading every five minutes over `[start, end)` seconds in, the way a worn watch samples.
    func worn(_ start: TimeInterval, _ end: TimeInterval) -> [Date] {
        stride(from: start, to: end, by: 300).map { from.addingTimeInterval($0) }
    }

    func off(_ readings: [Date], openEnded: Bool = false) -> Double? {
        WristCoverage.offWristMinutes(readings: readings, from: from, to: to, openEnded: openEnded)
    }

    @Test("a watch worn all night is on the wrist all night")
    func wornAllNight() {
        #expect(off(worn(0, 12 * 3600)) == 0)
    }

    @Test("a six-hour silence is six hours off the wrist")
    func sixHourGap() {
        // Worn until 22:00, on the charger until 04:00, worn again after.
        // The gap runs from the last reading (21:55) to the next (04:00).
        #expect(off(worn(0, 3600) + worn(7 * 3600, 12 * 3600)) == 365.0)
    }

    @Test("the longest absence, not the sum — a shower and a charge are not one night off")
    func longestNotSum() {
        let readings = worn(0, 3600) + worn(3600 + 45 * 60, 5 * 3600) + worn(5 * 3600 + 50 * 60, 12 * 3600)
        // 45 + 5 min, then 50 + 5 min: the longer silence, alone.
        #expect(off(readings) == 55.0)
    }

    @Test("a gap under the threshold is a worn watch sampling slowly, not an absence")
    func shortGapIsNotOffWrist() {
        #expect(off(worn(0, 3600) + worn(3600 + 25 * 60, 12 * 3600)) == 0)
    }

    @Test("the start counts: a watch put on at 03:00 was off from 21:00")
    func startCounts() {
        #expect(off(worn(6 * 3600, 12 * 3600)) == 360.0)
    }

    @Test("an open end is where the phone's copy of Health ends, not an absence")
    func openEndIsNotAGap() {
        // The last sample to ARRIVE was two hours before the window's end.
        let readings = worn(0, 10 * 3600)
        #expect(off(readings) == 125.0, "closed: the tail counts")
        #expect(off(readings, openEnded: true) == 0, "open: it does not")
    }

    @Test("no reading at all is nil — no watch and a watch in a drawer look the same")
    func noReadingsIsUnknown() {
        #expect(off([]) == nil)
        // Readings OUTSIDE the window are not evidence about it.
        #expect(off([from.addingTimeInterval(-60)]) == nil)
    }

    // MARK: The note — from the same inputs the battery reads

    /// A day with everything the watch measures, and a night on its charger.
    func inputs(offWrist: Double?) -> ScoringInputs {
        var i = ScoringInputs(sleepHours: 7, deepMinutes: 60, remMinutes: 90, activeCal: 420, restingHR: 52, hrvMs: 55)
        i.offWristMin = offWrist
        return i
    }

    @Test("five signals are counted off ScoringInputs, the object the score was built from")
    func signalsCount() {
        #expect(WristCoverage.signals(inputs(offWrist: nil)) == 5)
        #expect(WristCoverage.signals(ScoringInputs()) == 0)
        var noStages = inputs(offWrist: nil)
        noStages.deepMinutes = 0
        noStages.remMinutes = 0
        #expect(WristCoverage.signals(noStages) == 4)
    }

    @Test("the note speaks only when time off the wrist cost a signal")
    func noteNeedsBoth() throws {
        var lost = inputs(offWrist: 360)
        lost.deepMinutes = 0
        lost.remMinutes = 0
        let note = try #require(OffWristNote.make(lost))
        #expect(note.sentence == "Your watch was off your wrist for 6 h — readiness is from 4 signals, not 5.")
        #expect(note.short == "off wrist 6 h · 4 of 5")
        #expect(note.signalsText == "4 of 5")
        // Off the wrist, nothing lost: the reading is the reading.
        #expect(OffWristNote.make(inputs(offWrist: 360)) == nil)
        // A signal lost with the watch on: not the watch's absence.
        var worn = lost
        worn.offWristMin = 0
        #expect(OffWristNote.make(worn) == nil)
        worn.offWristMin = nil
        #expect(OffWristNote.make(worn) == nil)
        // A shower is not an absence.
        worn.offWristMin = 45
        #expect(OffWristNote.make(worn) == nil)
        // Rounded to whole hours, never below one.
        worn.offWristMin = 60
        #expect(OffWristNote.make(worn)?.hours == 1)
    }

    @Test("the sentence counts in English: one signal, and none")
    func plurals() {
        #expect(OffWristNote(hours: 9, signals: 1).sentence.hasSuffix("readiness is from 1 signal, not 5."))
        #expect(OffWristNote(hours: 9, signals: 0).sentence.hasSuffix("readiness has none of its 5 watch signals."))
    }

    @Test("the note goes on the wire in two short keys, and `of` is never sent")
    func wireKeys() throws {
        let data = try JSONEncoder().encode(OffWristNote(hours: 6, signals: 3))
        #expect(String(decoding: data, as: UTF8.self).count <= 13)
        let back = try JSONDecoder().decode(OffWristNote.self, from: Data(#"{"h":6,"s":3}"#.utf8))
        #expect(back == OffWristNote(hours: 6, signals: 3) && back.of == 5)
    }

    // MARK: The battery

    @Test("a night the watch never saw charges from HRV and resting HR, not from zero hours")
    func offWristNightIsNotZeroHours() {
        let base = ScoringInputs(sleepHours: 0, hrvZ: 0, rhrZ: 0)
        var offWrist = base
        offWrist.offWristMin = 360

        let zero = Battery.sleepQualityParts(base)
        let unmeasured = Battery.sleepQualityParts(offWrist)
        // v9 unchanged without the fact: 0.45·0 + 0.15·0 + 0.25·0.75 + 0.15·0.75.
        #expect(abs(zero.quality - 0.30) < 1e-9)
        // The two measured terms, renormalised over their own weight: both at
        // baseline is the neutral 0.75.
        #expect(abs(unmeasured.quality - 0.75) < 1e-9)
        // What was measured still reads as measured.
        #expect(unmeasured.ratio == 0 && unmeasured.stagesQ == 0)
        #expect(Battery.computeMorningCharge(sleepQuality: unmeasured.quality)
                > Battery.computeMorningCharge(sleepQuality: zero.quality))
    }

    @Test("the fact never touches a recorded night, a short absence, or nil")
    func factIsInertOtherwise() {
        let slept = ScoringInputs(sleepHours: 7, deepMinutes: 60, remMinutes: 90, hrvZ: 1, rhrZ: -1)
        var flagged = slept
        flagged.offWristMin = 360
        #expect(Battery.sleepQualityParts(flagged) == Battery.sleepQualityParts(slept))
        var shower = ScoringInputs(sleepHours: 0)
        shower.offWristMin = 45
        #expect(Battery.sleepQualityParts(shower) == Battery.sleepQualityParts(ScoringInputs(sleepHours: 0)))
    }

    @Test("the unmeasured charge stays inside the v9 budget")
    func unmeasuredStaysInBand() {
        for z in [-9.0, -2, 0, 2, 9] {
            var i = ScoringInputs(sleepHours: 0, hrvZ: z, rhrZ: -z)
            i.offWristMin = 600
            let q = Battery.sleepQualityParts(i).quality
            #expect(q >= 0 && q <= 1)
            let charge = Battery.computeMorningCharge(sleepQuality: q)
            #expect(charge >= Battery.defaults.wakeMin && charge <= 100)
        }
    }

    // MARK: The export

    @Test("the export's recomputed charge replays the scorer's off-wrist night")
    func exportReplaysTheFact() throws {
        var day = ExportDay(date: "2026-09-01", weekdayLabel: "Tue", isTrainingDay: false, nutritionEstimated: false)
        day.readiness = ExportReadiness(hrvZ: 0, rhrZ: 0, load: nil, acute: nil, chronic: nil, acwr: nil,
                                        weeklyLoad: nil, monotony: nil, strain: nil, strainZ: nil)
        let plain = try #require(Derived.batteryDays(Self.input([day])).first)
        day.offWristMin = 360
        let off = try #require(Derived.batteryDays(Self.input([day])).first)
        #expect(off.morningCharge > plain.morningCharge)
    }

    static func input(_ days: [ExportDay]) -> WeeklyExportInput {
        WeeklyExportInput(
            weekStart: "2026-09-01", weekEnd: "2026-09-07", weekLabel: nil,
            programLabel: "Upper/Lower", calorieGoal: nil, proteinGoalG: nil,
            stepsGoal: nil, sleepGoalHours: nil, waterGoalMl: nil, phaseLabel: nil,
            targetPeriods: nil, days: days, sessions: [], volumeByMuscle: [],
            tonnageByMuscle: nil, doms: [], joints: nil, fatigue: nil, stress: nil,
            bodyComp: nil, cardio: nil, supplementProtocol: nil, ledger: nil,
            leverBaselineKcal: nil, anomalies: nil, protocolNotes: nil, insomnia: nil
        )
    }
}
