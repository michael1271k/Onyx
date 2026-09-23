import Foundation
import Testing
@testable import OnyxCore

/// A supplement's dose history — `DosePeriod`, `Supplements.doseAt` and the
/// append rule behind the editor.
///
/// ── THE DEFECT THIS PINS ────────────────────────────────────────────────────
/// `custom_supplements` held one dose and no date, so changing 300 mg to 200 mg
/// rewrote every day the item had ever been taken — last Tuesday's checklist,
/// its micronutrient credit and the export all said 200 mg.
@Suite("Dose history — a change starts today and leaves the past alone")
struct DoseHistoryTests {

    private static let magnesium = CustomSupplement(
        id: "m", name: "Magnesium", dose: "300 mg", time: "22:00",
        schedule: CustomSchedule(key: "magnesium"), doseAmount: 300, doseUnit: "mg"
    )

    private static func saved(_ c: CustomSupplement, dose: String, today: String) -> CustomSupplement {
        var next = c
        next.dose = dose
        next.dosePeriods = Supplements.dosePeriods(changing: c, to: next, today: today)
        return next
    }

    @Test("a row with no history reads its own dose on every date")
    func noHistoryIsTheRow() {
        let c = Self.magnesium
        #expect(Supplements.doseAt(c, on: "2020-01-01") == c)
        #expect(Supplements.doseAt(c, on: "2030-01-01") == c)
    }

    @Test("the day before a change reads the old dose; the day of it reads the new one")
    func changeIsExclusiveOfItsDay() {
        let c = Self.saved(Self.magnesium, dose: "200 mg", today: "2026-09-23")
        #expect(c.dosePeriods == [DosePeriod(until: "2026-09-23", dose: "300 mg", doseAmount: 300, doseUnit: "mg")])
        #expect(Supplements.doseAt(c, on: "2026-09-22").dose == "300 mg")
        #expect(Supplements.doseAt(c, on: "2026-09-22").doseAmount == 300)
        #expect(Supplements.doseAt(c, on: "2026-09-23").dose == "200 mg")
        #expect(Supplements.doseAt(c, on: "2026-10-01").dose == "200 mg")
    }

    @Test("three doses resolve in order, whatever order the list was stored in")
    func periodsResolveBySearchNotPosition() {
        var c = Self.saved(Self.magnesium, dose: "200 mg", today: "2026-09-10")
        c = Self.saved(c, dose: "100 mg", today: "2026-09-20")
        #expect(c.dosePeriods?.map(\.dose) == ["300 mg", "200 mg"])
        c.dosePeriods?.reverse()
        #expect(Supplements.doseAt(c, on: "2026-09-09").dose == "300 mg")
        #expect(Supplements.doseAt(c, on: "2026-09-10").dose == "200 mg")
        #expect(Supplements.doseAt(c, on: "2026-09-19").dose == "200 mg")
        #expect(Supplements.doseAt(c, on: "2026-09-20").dose == "100 mg")
    }

    @Test("two changes in one day record the dose the day started with, once")
    func secondChangeTheSameDayClosesNothing() {
        var c = Self.saved(Self.magnesium, dose: "200 mg", today: "2026-09-23")
        c = Self.saved(c, dose: "250 mg", today: "2026-09-23")
        #expect(c.dosePeriods?.map(\.dose) == ["300 mg"])
        #expect(Supplements.doseAt(c, on: "2026-09-22").dose == "300 mg")
        #expect(Supplements.doseAt(c, on: "2026-09-23").dose == "250 mg")
    }

    @Test("changing back the same day is an undo, and leaves an empty list rather than nil")
    func changingBackIsAnUndo() {
        var c = Self.saved(Self.magnesium, dose: "200 mg", today: "2026-09-23")
        c = Self.saved(c, dose: "300 mg", today: "2026-09-23")
        #expect(c.dosePeriods == [])
        #expect(Supplements.doseAt(c, on: "2026-09-22").dose == "300 mg")
    }

    @Test("an edit that leaves the dose alone closes nothing")
    func nameOnlyEditIsNotADoseChange() {
        var next = Self.magnesium
        next.name = "Magnesium glycinate"
        next.doseAmount = nil   // the editor's copy; the string is what readers parse
        #expect(Supplements.dosePeriods(changing: Self.magnesium, to: next, today: "2026-09-23") == nil)
    }

    @Test("a dose the editor only re-spells is not a change")
    func respelledDoseIsNotAChange() {
        // A row the web wrote, saved back by the editor after a time edit.
        let web = CustomSupplement(id: "o", name: "Omega-3", dose: "2 Caps", schedule: CustomSchedule(key: "omega3"))
        var next = web
        next.dose = Supplements.doseText(amount: 2, unit: .cap)
        next.time = "08:00"
        #expect(next.dose == "2 caps")
        #expect(Supplements.dosePeriods(changing: web, to: next, today: "2026-09-23") == nil)
    }

    @Test("a period closed on a clock running ahead is closed today, so today reads the new dose")
    func futurePeriodIsClampedToToday() {
        var c = Self.saved(Self.magnesium, dose: "200 mg", today: "2026-09-24")   // the other device's tomorrow
        c = Self.saved(c, dose: "150 mg", today: "2026-09-23")
        #expect(c.dosePeriods?.map(\.until) == ["2026-09-23"])
        #expect(Supplements.doseAt(c, on: "2026-09-22").dose == "300 mg")
        #expect(Supplements.doseAt(c, on: "2026-09-23").dose == "150 mg")
    }

    @Test("a training / rest dose is history too")
    func perDayDosesAreRecorded() {
        var c = Self.magnesium
        c.schedule?.trainingDose = "400 mg"
        var next = c
        next.schedule?.trainingDose = "500 mg"
        next.dosePeriods = Supplements.dosePeriods(changing: c, to: next, today: "2026-09-23")
        #expect(Supplements.customDose(Supplements.doseAt(next, on: "2026-09-22"), isTraining: true) == "400 mg")
        #expect(Supplements.customDose(Supplements.doseAt(next, on: "2026-09-23"), isTraining: true) == "500 mg")
        // The key survives the swap — it is the join to every log row.
        #expect(Supplements.key(of: Supplements.doseAt(next, on: "2026-09-22")) == "magnesium")
    }

    @Test("the slots a day renders carry the dose in force that day")
    func slotsCarryTheDayDose() {
        let c = Self.saved(Self.magnesium, dose: "200 mg", today: "2026-09-23")
        let before = Supplements.customSlotsForDate([c], on: "2026-09-22", weekday: 2)
        let after = Supplements.customSlotsForDate([c], on: "2026-09-23", weekday: 3)
        #expect(before.flatMap(\.items).map(\.dose) == ["300 mg"])
        #expect(after.flatMap(\.items).map(\.dose) == ["200 mg"])
    }

    @Test("a reminder per slot time, only for doses nobody has answered, at the day's dose")
    func remindersSkipAnsweredDoses() {
        let zinc = CustomSupplement(id: "z", name: "Zinc", dose: "15 mg", time: "22:00", schedule: CustomSchedule(key: "zinc"))
        let d3 = CustomSupplement(id: "d", name: "D3", dose: "5000 IU", time: "08:00", schedule: CustomSchedule(key: "d3"))
        let untimed = CustomSupplement(id: "u", name: "Fibre", dose: "5 g", schedule: CustomSchedule(key: "fibre"))
        let magnesium = Self.saved(Self.magnesium, dose: "200 mg", today: "2026-09-23")
        let slots = Supplements.customSlotsForDate([magnesium, zinc, d3, untimed], on: "2026-09-22", weekday: 2)
        let doses = Supplements.doses(slots: slots, log: [DoseLogEntry(itemKey: "d3", taken: true)], clock: .future)
        #expect(Supplements.reminders(doses) == [
            StackReminder(time: "22:00", title: "Stack · 22:00", body: "Magnesium 300 mg, Zinc 15 mg"),
        ])
    }

    @Test("the jsonb round-trips camelCase, and a row from before 7.13.0 decodes with no history")
    func wireShape() throws {
        let c = Self.saved(Self.magnesium, dose: "200 mg", today: "2026-09-23")
        let json = try JSONEncoder().encode(c.dosePeriods)
        #expect(String(decoding: json, as: UTF8.self).contains("\"until\":\"2026-09-23\""))
        #expect(String(decoding: json, as: UTF8.self).contains("\"doseAmount\":300"))
        let old = try JSONDecoder().decode(
            CustomSupplement.self, from: Data(#"{"id":"m","name":"Magnesium","dose":"300 mg"}"#.utf8))
        #expect(old.dosePeriods == nil)
    }
}
