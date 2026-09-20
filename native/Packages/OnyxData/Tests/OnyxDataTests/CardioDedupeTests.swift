import Foundation
import Testing
@testable import OnyxData

// ─────────────────────────────────────────────────────────────────────────────
// One physical bout is one row.
//
// The week that prompted this reported `228 bouts · 40,559 kcal` for a handful
// of walks: the HealthKit ingest had been re-run after a restore, `cardio_logs`
// held twenty-odd copies of each bout, and the export's dedupe key contained
// `created_at` — which on a re-imported or web-era row is the INSTANT OF THE
// IMPORT and therefore different on every copy. The key matched nothing and
// every total in the document was multiplied.
// ─────────────────────────────────────────────────────────────────────────────

private func bout(
    _ id: String, at seconds: TimeInterval, uuid: String? = nil,
    kind: String = "walk", durationMin: Double? = 42, distanceM: Double? = 3600,
    kcal: Double? = 178, date: String = "2026-09-17"
) -> CardioLogRow {
    CardioLogRow(
        id: id, userId: "u", date: date, kind: kind,
        distanceM: distanceM, durationMin: durationMin,
        fromHealthkit: true, createdAt: Date(timeIntervalSince1970: seconds),
        activeKcal: kcal, hkUuid: uuid
    )
}

@Suite("Cardio dedupe — the key that stopped trusting the clock")
struct CardioDedupeTests {

    @Test("a re-import whose stamp drifted is still one bout")
    func aDriftingStampDoesNotMintANewBout() {
        // The same walk, imported three times, each pass writing the moment of
        // the import. Under the old key these were three distinct rows.
        let rows = [
            bout("a", at: 1_000, uuid: "AB-CD"),
            bout("b", at: 50_000, uuid: "ab-cd"),
            bout("c", at: 90_000, uuid: "AB-CD"),
        ]
        let out = WeeklyExportBuilder.dedupeCardio(rows)
        #expect(out.count == 1)
        // The FIRST survives, so an id other tables may reference is kept.
        #expect(out.first?.id == "a")
    }

    @Test("a legacy row with no uuid is deduped on what the bout physically was")
    func thePhysicalIdentityIsEnough() {
        let rows = [bout("a", at: 1_000), bout("b", at: 77_000), bout("c", at: 90_000)]
        #expect(WeeklyExportBuilder.dedupeCardio(rows).count == 1)
    }

    /// ── `kcal` IS NOT AN IDENTITY, AND THAT IS THE POINT ───────────────────
    /// It was in the key, compared byte for byte, and that is how two copies of
    /// one Tuesday walk both reached the document: Health re-states a bout's
    /// energy as later samples arrive, so the copies agreed on 32 minutes and
    /// 3.35 km and disagreed on the calories. Energy is the one figure the
    /// source revises, so it is out of the key entirely and `e` now folds into
    /// `a` — deliberately, and the reason it is worth one test of its own.
    @Test("two genuinely different bouts survive; two that differ only in energy do not")
    func differentBoutsAreNotCollapsed() {
        let rows = [
            bout("a", at: 1_000, kind: "walk"),
            bout("b", at: 1_000, kind: "run"),
            bout("c", at: 1_000, kind: "walk", durationMin: 18),
            bout("d", at: 1_000, kind: "walk", distanceM: 900),
            bout("e", at: 1_000, kind: "walk", kcal: 55),
            bout("f", at: 1_000, kind: "walk", date: "2026-09-18"),
        ]
        let out = WeeklyExportBuilder.dedupeCardio(rows)
        #expect(out.count == 5)
        #expect(!out.map(\.id).contains("e"))
    }

    /// The defect this wave was given: two copies of one walk, minutes apart in
    /// their stamps and a few calories apart in their energy, both exported.
    @Test("a re-import whose stamp AND energy drifted is one bout, kept at the earliest")
    func aDriftedCopyFolds() {
        let rows = [
            bout("a", at: 68_280, durationMin: 32, distanceM: 3350, kcal: 190),
            bout("b", at: 82_020, durationMin: 32, distanceM: 3350, kcal: 196),
        ]
        let out = WeeklyExportBuilder.dedupeCardio(rows)
        #expect(out.count == 1)
        // The fetch is ordered by `created_at`, so the first row IS the
        // earliest start — and keeping it keeps an id other tables may hold.
        #expect(out.first?.id == "a")
    }

    /// A minute either way, and a hundred metres.
    @Test("the tolerance is a tolerance, not an equality")
    func toleranceHolds() {
        let within = [
            bout("a", at: 1_000, durationMin: 32, distanceM: 3350),
            bout("b", at: 2_000, durationMin: 32.9, distanceM: 3430),
        ]
        #expect(WeeklyExportBuilder.dedupeCardio(within).count == 1)
        let beyond = [
            bout("a", at: 1_000, durationMin: 32, distanceM: 3350),
            bout("b", at: 2_000, durationMin: 34, distanceM: 3350),
        ]
        #expect(WeeklyExportBuilder.dedupeCardio(beyond).count == 2)
    }

    /// One row measured a distance and the other did not. An absence is a
    /// disagreement, not a wildcard.
    @Test("a measurement present on one row and absent on the other is not a match")
    func absenceIsNotAWildcard() {
        let rows = [
            bout("a", at: 1_000, durationMin: 32, distanceM: 3350),
            bout("b", at: 2_000, durationMin: 32, distanceM: nil),
        ]
        #expect(WeeklyExportBuilder.dedupeCardio(rows).count == 2)
    }

    @Test("a row with no uuid and no measurement at all is never deduped")
    func anEmptyRowIsNotAKey() {
        /* A key built from absences is the same key for every such row, so a
           Monday cycle and a Friday swim would collapse into one and the
           document would report the collapse as a duplicate removed. */
        let rows = [
            bout("a", at: 1_000, durationMin: nil, distanceM: nil, kcal: nil),
            bout("b", at: 2_000, durationMin: nil, distanceM: nil, kcal: nil),
        ]
        #expect(WeeklyExportBuilder.dedupeCardio(rows).count == 2)
    }

    @Test("a uuid beats the measurements — a corrected bout is not a second one")
    func theUuidLeads() {
        // The same workout, re-read after Health finished writing its distance.
        let rows = [
            bout("a", at: 1_000, uuid: "x", distanceM: nil, kcal: nil),
            bout("b", at: 1_000, uuid: "x", distanceM: 3600, kcal: 178),
        ]
        #expect(WeeklyExportBuilder.dedupeCardio(rows).count == 1)
    }
}
