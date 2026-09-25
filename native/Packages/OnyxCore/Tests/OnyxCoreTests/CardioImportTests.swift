import Foundation
import Testing
@testable import OnyxCore

/// The rule that decides whether an imported bout OVERWRITES a row.
///
/// It is tested at this weight because it is the one part of the cardio import
/// that can destroy something: a false match writes over a bout the founder
/// typed, and a missed match leaves the ledger with two of everything.
@Suite("Cardio import")
struct CardioImportTests {

    private let day = "2026-09-03"

    private func at(_ hour: Int, _ minute: Int) -> Date {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 9; parts.day = 3
        parts.hour = hour; parts.minute = minute
        return Calendar(identifier: .gregorian).date(from: parts)!
    }

    private func imported(
        _ id: String, kind: String = CardioImport.walk, at start: Date, minutes: Double? = 40
    ) -> CardioImport.Existing {
        .init(id: id, date: day, kind: kind, durationMin: minutes, createdAt: start, fromHealthkit: true)
    }

    private func typed(
        _ id: String, kind: String = CardioImport.walk, minutes: Double?, createdAt: Date? = nil
    ) -> CardioImport.Existing {
        .init(id: id, date: day, kind: kind, durationMin: minutes, createdAt: createdAt, fromHealthkit: false)
    }

    private func match(
        kind: String = CardioImport.walk, start: Date, minutes: Double? = 40,
        in rows: [CardioImport.Existing]
    ) -> CardioImport.Existing? {
        CardioImport.matchingRow(kind: kind, start: start, durationMin: minutes, date: day, in: rows)
    }

    // MARK: - The precise rule, over imported rows

    @Test("the same bout, arriving four minutes off, is the same bout")
    func withinTheWindow() {
        let rows = [imported("a", at: at(7, 12))]
        #expect(match(start: at(7, 16), in: rows)?.id == "a")
    }

    @Test("six minutes apart is a second bout, not a duplicate")
    func outsideTheWindow() {
        let rows = [imported("a", at: at(7, 12))]
        #expect(match(start: at(7, 18), in: rows) == nil)
    }

    @Test("exactly five minutes is inside — the window is inclusive")
    func onTheBoundary() {
        let rows = [imported("a", at: at(7, 12))]
        #expect(match(start: at(7, 17), in: rows)?.id == "a")
    }

    @Test("a day of hourly walks maps one to one, closest first")
    func closestWins() {
        // The failure this prevents: every walk in the day matching the first
        // row in the array and eleven bouts collapsing onto one.
        let rows = [
            imported("07", at: at(7, 0)),
            imported("08", at: at(8, 0)),
            imported("09", at: at(9, 0)),
        ]
        #expect(match(start: at(8, 2), in: rows)?.id == "08")
        #expect(match(start: at(9, 1), in: rows)?.id == "09")
    }

    @Test("a walk never matches a ride, however close they start")
    func kindSeparates() {
        let rows = [imported("a", kind: CardioImport.cycling, at: at(7, 12))]
        #expect(match(kind: CardioImport.walk, start: at(7, 12), in: rows) == nil)
    }

    @Test("a bout on another day is another bout")
    func dateSeparates() {
        let other = CardioImport.Existing(
            id: "a", date: "2026-09-02", kind: CardioImport.walk, durationMin: 40,
            createdAt: at(7, 12), fromHealthkit: true
        )
        #expect(match(start: at(7, 12), in: [other]) == nil)
    }

    // MARK: - The fuzzy rule, over rows a person typed

    @Test("a hand-typed bout is matched on duration, because its timestamp is not a start")
    func manualMatchesOnDuration() {
        // Typed up at 21:00 for a walk done at 07:12 — thirteen hours from
        // itself, which is why the start-time rule cannot be used here.
        let rows = [typed("m", minutes: 41, createdAt: at(21, 0))]
        #expect(match(start: at(7, 12), minutes: 40, in: rows)?.id == "m")
    }

    @Test("a hand-typed bout of a different length is a different bout")
    func manualDurationSeparates() {
        let rows = [typed("m", minutes: 62, createdAt: at(21, 0))]
        #expect(match(start: at(7, 12), minutes: 40, in: rows) == nil)
    }

    @Test("an imported row wins over a hand-typed one that would also match")
    func importedRuleLeads() {
        // Both are candidates; the precise rule is the one that should decide,
        // because it is the one that knows WHICH bout it is looking at.
        let rows = [
            typed("m", minutes: 40, createdAt: at(21, 0)),
            imported("a", at: at(7, 14)),
        ]
        #expect(match(start: at(7, 12), minutes: 40, in: rows)?.id == "a")
    }

    // MARK: - Absence

    @Test("unknown duration never matches a hand-typed row")
    func nilDurationNeverMatches() {
        #expect(match(start: at(7, 12), minutes: nil, in: [typed("m", minutes: 40)]) == nil)
        #expect(match(start: at(7, 12), minutes: 40, in: [typed("m", minutes: nil)]) == nil)
    }

    @Test("an imported row with no stored start cannot be matched on time")
    func nilCreatedAtNeverMatches() {
        // It also must not fall through to the duration rule: that rule is only
        // safe against rows whose `created_at` is an insertion instant, and an
        // imported row's is not.
        let rows = [CardioImport.Existing(
            id: "a", date: day, kind: CardioImport.walk, durationMin: 40,
            createdAt: nil, fromHealthkit: true
        )]
        #expect(match(start: at(7, 12), minutes: 40, in: rows) == nil)
    }

    @Test("an empty ledger matches nothing")
    func emptyLedger() {
        #expect(match(start: at(7, 12), in: []) == nil)
    }

    @Test("the offered kinds lead with the two the founder logs")
    func offeredOrder() {
        #expect(CardioImport.offered.first == CardioImport.walk)
        #expect(CardioImport.offered.count == 7)
        #expect(Set(CardioImport.offered).count == 7, "no key offered twice")
    }

    // MARK: - The key (W1)

    private func keyed(
        _ id: String, uuid: String, kind: String = CardioImport.walk,
        at start: Date? = nil, minutes: Double? = 40
    ) -> CardioImport.Existing {
        .init(id: id, date: day, kind: kind, durationMin: minutes,
              createdAt: start, fromHealthkit: true, hkUuid: uuid)
    }

    @Test("the uuid wins outright, whatever the window says")
    func keyBeatsTheWindow() {
        // Nine hours apart and matched anyway. This is the failure the window
        // could never catch: a row whose `created_at` did not survive the round
        // trip, or came back shifted, is still the same physical bout.
        let rows = [keyed("a", uuid: "HK-1", at: at(22, 0))]
        #expect(CardioImport.matchingRow(
            hkUuid: "HK-1", kind: CardioImport.walk, start: at(7, 12),
            durationMin: 40, date: day, in: rows
        )?.id == "a")
    }

    @Test("a row with no start at all is still matched by its key")
    func keyBeatsAMissingStart() {
        // `created_at` nil is exactly the shape that made the ingest re-insert:
        // the precise branch skips the row and the fuzzy one only looks at
        // hand-typed rows, so an imported row with no start matched nothing.
        let rows = [keyed("a", uuid: "HK-1", at: nil)]
        #expect(CardioImport.matchingRow(
            hkUuid: "HK-1", kind: CardioImport.walk, start: at(7, 12),
            durationMin: 40, date: day, in: rows
        )?.id == "a")
    }

    @Test("a different kind is still the same bout when the key agrees")
    func keyIgnoresKind() {
        // A build that maps an activity type differently has not made a second
        // walk happen. Re-inserting under the new kind is the duplicate.
        let rows = [keyed("a", uuid: "HK-1", kind: CardioImport.hiit, at: at(7, 12))]
        #expect(CardioImport.matchingRow(
            hkUuid: "HK-1", kind: CardioImport.run, start: at(7, 12),
            durationMin: 40, date: day, in: rows
        )?.id == "a")
    }

    @Test("two unkeyed rows are not each other — nil never matches nil")
    func nilKeysNeverCollide() {
        // Both of these are pre-migration imports an hour apart. If absence
        // counted as equality every unkeyed bout on the day would fold into one.
        let rows = [imported("a", at: at(7, 12)), imported("b", at: at(11, 30))]
        #expect(CardioImport.matchingRow(
            hkUuid: nil, kind: CardioImport.walk, start: at(11, 31),
            durationMin: 40, date: day, in: rows
        )?.id == "b")
    }

    @Test("an unrecognised key falls through to the window, not to nil")
    func unknownKeyFallsThrough() {
        // The bout is new to the key but the day already holds the row it came
        // from, imported before the column existed. The window still owns that
        // case and must keep owning it — that row is what gets the key stamped.
        let rows = [imported("a", at: at(7, 12))]
        #expect(CardioImport.matchingRow(
            hkUuid: "HK-NEW", kind: CardioImport.walk, start: at(7, 14),
            durationMin: 40, date: day, in: rows
        )?.id == "a")
    }
}

// MARK: - Overhaul C2 · a treadmill is a walk indoors

extension CardioImportTests {

    @Test("a treadmill bout matches the walk row an older build filed it as")
    func treadmillMatchesItsWalk() {
        let rows = [imported("a", at: at(7, 12))]
        #expect(match(kind: CardioImport.treadmill, start: at(7, 14), in: rows)?.id == "a")
        // And nothing else crosses: a run is never a walk.
        #expect(match(kind: CardioImport.run, start: at(7, 14), in: rows) == nil)
        #expect(CardioImport.sameActivity(CardioImport.walk, CardioImport.treadmill))
        #expect(CardioImport.sameActivity(CardioImport.treadmill, CardioImport.walk))
        #expect(!CardioImport.sameActivity(CardioImport.treadmill, CardioImport.run))
        #expect(CardioImport.sameActivity(CardioImport.hiit, CardioImport.hiit))
    }

    // MARK: - The opener is the bout you did (Precision A2, Q5)

    @Test("the opener repeats the ACTUAL bout; only a three-hour sanity ceiling cuts it")
    func openerIsTheActualBout() throws {
        // A 24-minute bout used to come back cut to ten minutes and 1.12 km —
        // the "1 km / 10 min" the founder never walked.
        let walk = WarmupCardio.Bout(name: "Treadmill", durationSec: 1_440, distanceKm: 2.69, inclinePct: 3)
        #expect(WarmupCardio.seed(from: walk) == walk)
        // Past three hours it is a logging error, not a warm-up: cut, pace kept.
        let absurd = WarmupCardio.Bout(name: "Treadmill", durationSec: 21_600, distanceKm: 30)
        let cut = try #require(WarmupCardio.seed(from: absurd))
        #expect(cut.durationSec == 10_800)
        #expect(cut.distanceKm == 15)
        #expect(WarmupCardio.seed(from: WarmupCardio.Bout(name: "Treadmill", durationSec: 0)) == nil)
    }
}
