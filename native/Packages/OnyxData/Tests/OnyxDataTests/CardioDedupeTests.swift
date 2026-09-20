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

    @Test("two genuinely different bouts survive")
    func differentBoutsAreNotCollapsed() {
        let rows = [
            bout("a", at: 1_000, kind: "walk"),
            bout("b", at: 1_000, kind: "run"),
            bout("c", at: 1_000, kind: "walk", durationMin: 18),
            bout("d", at: 1_000, kind: "walk", distanceM: 900),
            bout("e", at: 1_000, kind: "walk", kcal: 55),
            bout("f", at: 1_000, kind: "walk", date: "2026-09-18"),
        ]
        #expect(WeeklyExportBuilder.dedupeCardio(rows).count == 6)
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
