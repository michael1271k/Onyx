import Foundation
import Testing
@testable import OnyxCore

/// W1: the two things a supplement row stores that a locale or a credit rule
/// could quietly get wrong — the time it is taken at, and the calories it
/// carries.
@Suite("Supplement time and macros — the stored string, and the day's ring")
struct SupplementMacroTests {

    // MARK: - The stored time

    /// The wheel hands back a `Date`; the column stores `"HH:mm"`. Every
    /// region writes the same six characters, because `customSlotsForDate`
    /// GROUPS BY this string — a "6:30 PM" mints a slot that never merges with
    /// the 18:30 one beside it.
    @Test("a wheel Date serialises to zero-padded 24-hour, whatever the locale")
    func timeStringIsLocaleIndependent() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Lisbon"))
        let evening = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 18, minute: 30))
        )
        #expect(Supplements.slotTimeString(evening, calendar: calendar) == "18:30")

        // The same instant, read through calendars whose locales spell a time
        // of day very differently. The output is arithmetic, so it cannot move.
        for identifier in ["en_US", "ar_EG", "fa_IR", "de_DE", "ja_JP"] {
            var localised = calendar
            localised.locale = Locale(identifier: identifier)
            #expect(
                Supplements.slotTimeString(evening, calendar: localised) == "18:30",
                "\(identifier) must still store 18:30"
            )
        }
    }

    @Test("midnight and one minute past it keep both digits")
    func timeStringPadsBothFields() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let midnight = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 0, minute: 0))
        )
        let justPast = try #require(calendar.date(byAdding: .minute, value: 1, to: midnight))
        #expect(Supplements.slotTimeString(midnight, calendar: calendar) == "00:00")
        #expect(Supplements.slotTimeString(justPast, calendar: calendar) == "00:01")
    }

    /// The round trip the editor performs on every open and every save.
    @Test("a stored time parses back to the same wall clock, and round-trips")
    func timeRoundTrips() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Lisbon"))
        let anchor = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 11, minute: 5))
        )
        for stored in ["00:00", "06:05", "09:30", "18:30", "22:00", "23:59"] {
            let parsed = try #require(Supplements.slotTime(from: stored, calendar: calendar, now: anchor))
            #expect(Supplements.slotTimeString(parsed, calendar: calendar) == stored)
        }
    }

    /// A blank column is a real state — the "—" bucket that sorts first — so
    /// the parser must refuse rather than invent a time.
    @Test("nothing the clock cannot hold comes back as a time")
    func timeParserRefusesNonsense() {
        for stored in ["", "   ", "—", "6:30 PM", "24:00", "18:60", "-1:30", "1830", "18:3a", "18:30:00"] {
            #expect(Supplements.slotTime(from: stored) == nil, "\(stored.debugDescription) is not a time")
        }
        // Whitespace around a real one is trimmed, as the editor's own save does.
        #expect(Supplements.slotTime(from: " 18:30 ") != nil)
    }

    /// The whole point of the format: two rows typed at the same minute land in
    /// ONE slot.
    @Test("two rows serialised from the same minute share a slot")
    func sameMinuteIsOneSlot() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Lisbon"))
        let evening = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 18, minute: 30))
        )
        let stored = Supplements.slotTimeString(evening, calendar: calendar)
        let rows = [
            CustomSupplement(id: "a", name: "Psyllium Husk", dose: "5 g", time: stored),
            CustomSupplement(id: "b", name: "Magnesium", dose: "300 mg", time: stored),
        ]
        let slots = Supplements.customSlotsForDate(rows, on: "2026-09-10", weekday: 4)
        #expect(slots.count == 1)
        #expect(slots.first?.time == "18:30")
        #expect(slots.first?.items.count == 2)
    }

    // MARK: - The macros

    /// The founder's row: 5 g of a 9 g serving, stored per dose.
    private static let psyllium: [String: Double] = [
        "kcal": 16.7, "carbs": 4.4, "fiber": 3.9, "protein": 0, "fat": 0,
        "sodium": 5.6, "iron": 0.83, "potassium": 50,
    ]

    private static func dose(_ state: DoseState, dose: String = "5 g") -> SupplementDose {
        SupplementDose(
            key: "psyllium", name: "Psyllium Husk Powder", dose: dose,
            slotKey: "stack-18:30", slotLabel: "Stack", slotTime: "18:30",
            customId: "psyllium-row", state: state
        )
    }

    @Test("a taken dose delivers its calories, carbohydrate and fibre")
    func takenDoseCounts() {
        let payloads = ["psyllium": Self.psyllium]
        let macros = SupplementNutrients.macros([Self.dose(.taken)], payloads: payloads)
        #expect(abs(macros.kcal - 16.7) < 0.001)
        #expect(abs(macros.carbs - 4.4) < 0.001)
        #expect(macros.protein == 0)
        #expect(macros.fat == 0)

        // Fibre is a GRID row, not a ring figure, so it arrives through
        // `credit` — the same doses, the same rule, the other surface.
        let micros = SupplementNutrients.credit([Self.dose(.taken)], payloads: payloads)
        #expect(abs((micros["fiber"] ?? 0) - 3.9) < 0.001)
        #expect(abs((micros["potassium"] ?? 0) - 50) < 0.001)
    }

    /// The rule the ring and the grid share: `taken` and `due` count, `later`
    /// and `skipped` do not. A 22:00 dose must not be in the day's calories at
    /// breakfast, and a refused one must never be.
    @Test("the four states credit exactly as the micronutrients do")
    func statesMatchTheMicroRule() {
        let payloads = ["psyllium": Self.psyllium]
        for state in [DoseState.taken, .due] {
            #expect(SupplementNutrients.macros([Self.dose(state)], payloads: payloads).kcal > 0, "\(state) counts")
        }
        for state in [DoseState.later, .skipped] {
            let macros = SupplementNutrients.macros([Self.dose(state)], payloads: payloads)
            #expect(macros.isZero, "\(state) must not reach the ring")
            #expect(SupplementNutrients.credit([Self.dose(state)], payloads: payloads).isEmpty, "\(state) must not reach the grid")
        }
    }

    /// The count multiplier is one rule, not two: a mass dose is already the
    /// total, a count dose delivers that many labels.
    @Test("a count dose multiplies the macros and a mass dose does not")
    func countMultiplierMatchesTheMicroRule() {
        let payloads = ["psyllium": Self.psyllium]
        let mass = SupplementNutrients.macros([Self.dose(.taken, dose: "5 g")], payloads: payloads)
        let counted = SupplementNutrients.macros([Self.dose(.taken, dose: "2 scoops")], payloads: payloads)
        #expect(abs(counted.kcal - mass.kcal * 2) < 0.001)

        let countedMicros = SupplementNutrients.credit([Self.dose(.taken, dose: "2 scoops")], payloads: payloads)
        #expect(abs((countedMicros["fiber"] ?? 0) - 3.9 * 2) < 0.001)
    }

    /// Every seeded item in the legacy table is a pill with no calories, so the
    /// ring must not move for a stack that predates this wave.
    @Test("a payload with no macro keys leaves the ring alone")
    func micronutrientOnlyPayloadIsZero() {
        let doses = [
            SupplementDose(key: "magnesium", name: "Magnesium", dose: "300 mg",
                           slotKey: "s", slotLabel: "Bed", slotTime: "22:00", state: .taken),
            SupplementDose(key: "creatine", name: "Creatine", dose: "5 g",
                           slotKey: "s", slotLabel: "Lunch", slotTime: "15:00", state: .due),
        ]
        #expect(SupplementNutrients.macros(doses).isZero)
        // …while still delivering what they actually carry.
        #expect(SupplementNutrients.credit(doses) == ["magnesium": 300, "creatine": 5000])
    }

    @Test("macros sum across every credited dose, once each")
    func macrosSumOnce() {
        let payloads = [
            "psyllium": Self.psyllium,
            "protein-shake": ["kcal": 120, "protein": 25, "carbs": 3, "fat": 1.5],
        ]
        let doses = [
            Self.dose(.taken),
            SupplementDose(key: "protein-shake", name: "Whey", dose: "1 scoop",
                           slotKey: "s", slotLabel: "Post", slotTime: "15:00", state: .due),
            // Refused, and therefore absent from both totals.
            SupplementDose(key: "protein-shake", name: "Whey", dose: "1 scoop",
                           slotKey: "s2", slotLabel: "Bed", slotTime: "22:00", state: .skipped),
        ]
        let macros = SupplementNutrients.macros(doses, payloads: payloads)
        #expect(abs(macros.kcal - (16.7 + 120)) < 0.001)
        #expect(abs(macros.protein - 25) < 0.001)
        #expect(abs(macros.carbs - (4.4 + 3)) < 0.001)
        #expect(abs(macros.fat - 1.5) < 0.001)
    }
}
