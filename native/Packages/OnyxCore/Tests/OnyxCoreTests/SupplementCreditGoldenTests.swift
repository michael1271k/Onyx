import Foundation
import Testing
@testable import OnyxCore

/// The credit rule, against the TypeScript that draws the same numbers on the
/// web. §W6: a dose counts once its slot has passed unless it was skipped, an
/// explicit "taken" counts at once, and an archived item is not scheduled.
@Suite("Supplement credit — archiving, the four states and the micros")
struct SupplementCreditGoldenTests {

    struct ArchiveRow: Decodable { let archived_at: String? }
    struct IdRow: Decodable { let id: String; let archived_at: String? }

    struct In: Decodable {
        let fn: String
        let row: ArchiveRow?
        let rows: [IdRow]?
        let date: String?
        let slots: [SupplementSlot]?
        let log: [DoseLogEntry]?
        let clock: DayClock?
        let resolved: [SupplementDose]?
        let payloads: [String: [String: Double]]?
        let customs: [CustomSupplement]?
    }

    struct Out: Decodable {
        let archived: Bool?
        let ids: [String]?
        let doses: [SupplementDose]?
        let micros: [String: Double]?
    }

    @Test("every case matches the TypeScript")
    func matchesGoldenVectors() throws {
        let fixture = try GoldenFixture<In, Out>.load("stack-credit")
        #expect(fixture.cases.count > 40)
        for c in fixture.cases {
            let i = c.input
            switch i.fn {
            case "isArchived":
                let row = CustomSupplement(id: "x", name: "x", dose: "x", archivedAt: i.row?.archived_at)
                #expect(Supplements.isArchived(row, on: i.date!) == c.expected.archived, "isArchived — \(c.name)")

            case "activeOn":
                let rows = (i.rows ?? []).map {
                    CustomSupplement(id: $0.id, name: $0.id, dose: "1", archivedAt: $0.archived_at)
                }
                #expect(Supplements.active(rows, on: i.date!).map(\.id) == c.expected.ids, "active — \(c.name)")

            case "doses":
                let out = Supplements.doses(slots: i.slots ?? [], log: i.log ?? [], clock: i.clock!)
                #expect(out == c.expected.doses, "doses — \(c.name)")

            case "creditNutrients":
                let out = SupplementNutrients.credit(i.resolved ?? [], payloads: i.payloads ?? [:])
                expectMicros(out, c.expected.micros ?? [:], c.name)

            case "nutrientPayloads":
                let keys = SupplementNutrients.payloads(i.customs ?? []).keys.sorted()
                #expect(keys == (c.expected.ids ?? []).sorted(), "payloads — \(c.name)")

            default:
                Issue.record("unhandled fn \(i.fn) — \(c.name)")
            }
        }
    }

    /// Two dictionaries of Doubles, compared the way `expectClose` compares one.
    private func expectMicros(_ got: [String: Double], _ want: [String: Double], _ name: String) {
        #expect(got.keys.sorted() == want.keys.sorted(), "micro keys — \(name)")
        for (key, value) in want {
            expectClose(got[key], value, "\(key) — \(name)")
        }
    }

    // MARK: - The rules the vector cannot state

    @Test("an archived item never reaches the day's slots, so it can never be credited")
    func archivedIsNeverScheduled() {
        let magnesium = CustomSupplement(
            id: "r-mag", name: "Magnesium", dose: "300 mg", time: "22:00",
            schedule: CustomSchedule(key: "magnesium"), micros: ["magnesium": 300],
            archivedAt: "2026-09-01T10:00:00Z"
        )
        let creatine = CustomSupplement(
            id: "r-cre", name: "Creatine", dose: "5 g", time: "15:00",
            schedule: CustomSchedule(key: "creatine"), micros: ["creatine": 5000]
        )
        let customs = [magnesium, creatine]
        let date = "2026-09-05"

        let active = Supplements.active(customs, on: date)
        #expect(active.map(\.id) == ["r-cre"])
        #expect(Supplements.archived(customs, on: date).map(\.id) == ["r-mag"])

        let slots = Supplements.customSlotsForDate(active, on: "2026-09-12", weekday: 6, isTraining: true)
        let credited = Supplements.creditedDoses(
            slots: slots, log: [], clock: .today(minutes: 23 * 60)
        )
        #expect(credited.map(\.key) == ["creatine"])
        #expect(SupplementNutrients.credit(credited, payloads: SupplementNutrients.payloads(active)) == ["creatine": 5000])
    }

    @Test("a dose skipped at 21:00 loses its micros; the rest of the day keeps them")
    func skipRemovesTheDose() {
        let slots = [
            SupplementSlot(key: "morning", time: "10:30", label: "Morning", accent: "#fff", items: [
                Supplement(key: "d3k2", name: "D3", dose: "125 mcg"),
            ]),
            SupplementSlot(key: "night", time: "22:00", label: "Before Bed", accent: "#fff", items: [
                Supplement(key: "magnesium", name: "Magnesium", dose: "300 mg"),
            ]),
        ]
        let clock = DayClock.today(minutes: 23 * 60)

        let whole = SupplementNutrients.credit(Supplements.creditedDoses(slots: slots, log: [], clock: clock))
        #expect(whole == ["vitaminD": 5000, "magnesium": 300])

        let skipped = SupplementNutrients.credit(Supplements.creditedDoses(
            slots: slots, log: [DoseLogEntry(itemKey: "magnesium", taken: false)], clock: clock
        ))
        #expect(skipped == ["vitaminD": 5000])
    }

    @Test("before its slot a dose is `later` and contributes nothing; ticking it counts at once")
    func slotTimeGatesTheCredit() {
        let slots = [SupplementSlot(key: "night", time: "22:00", label: "Before Bed", accent: "#fff", items: [
            Supplement(key: "magnesium", name: "Magnesium", dose: "300 mg"),
        ])]
        let morning = DayClock.today(minutes: 8 * 60)

        #expect(Supplements.doses(slots: slots, log: [], clock: morning).map(\.state) == [.later])
        #expect(SupplementNutrients.credit(Supplements.creditedDoses(slots: slots, log: [], clock: morning)).isEmpty)

        let ticked = [DoseLogEntry(itemKey: "magnesium", taken: true)]
        #expect(Supplements.doses(slots: slots, log: ticked, clock: morning).map(\.state) == [.taken])
        #expect(SupplementNutrients.credit(Supplements.creditedDoses(slots: slots, log: ticked, clock: morning)) == ["magnesium": 300])
    }
}
