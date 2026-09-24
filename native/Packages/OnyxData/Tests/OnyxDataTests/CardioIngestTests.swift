import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// A watch with bouts on it and a flat resting-energy rate.
private struct Wrist: HealthReading {
    var isAvailable = true
    var bouts: [WorkoutSample] = []
    /// kcal/min at rest — 1.2 is a plausible basal rate and, more usefully,
    /// makes a 50-minute walk's resting share exactly 60.
    var restingPerMinute: Double = 1.2
    func requestAuthorization(read: [String]) async throws -> Bool { true }
    func quantity(_ identifier: String, reduce: HealthReduce, start: Date, end: Date) async throws -> Double? {
        guard identifier == HealthCatalogue.restingEnergyIdentifier else { return nil }
        return restingPerMinute * end.timeIntervalSince(start) / 60
    }
    func sleepSamples(start: Date, end: Date) async throws -> [SleepSample] { [] }
    func workouts(start: Date, end: Date) async throws -> [WorkoutSample] {
        bouts.filter { $0.end >= start && $0.start <= end }
    }
}

@Suite("Cardio auto-ingest: the bout nobody had to type")
struct CardioIngestTests {

    private let user = "u1"
    /// 2026-09-04 14:00 UTC — inside the day the bouts below sit on.
    private let now = Date(timeIntervalSince1970: 1_788_530_400)
    private let today = "2026-09-04"
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    /// A bout on `today` starting at `hour`, `minutes` long.
    private func bout(
        hour: Int, minutes: Double, kind: String = CardioImport.walk,
        uuid: UUID = UUID(),
        distanceM: Double? = 4200, activeKcal: Double? = 210, avgHr: Double? = 112, elevationM: Double? = 86
    ) -> WorkoutSample {
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: hour))!
        return WorkoutSample(
            uuid: uuid,
            start: start, end: start.addingTimeInterval(minutes * 60), isLifting: false,
            cardioKind: kind, distanceM: distanceM, activeKcal: activeKcal,
            avgHr: avgHr, elevationM: elevationM
        )
    }

    private func ingest(_ db: AppDatabase, _ reader: any HealthReading) async throws -> CardioIngestReport {
        try await HealthSync(database: db, reader: reader, userId: user)
            .ingestCardio(day: today, now: now, calendar: calendar)
    }

    private func rows(_ db: AppDatabase) throws -> [CardioLogRow] {
        try db.cardioRows(userId: user, date: today)
    }

    // MARK: - Inserting

    @Test("a bout the ledger has never seen becomes a row, stamped with its own start")
    func insertsNewBout() async throws {
        let db = try store()
        let report = try await ingest(db, Wrist(bouts: [bout(hour: 7, minutes: 50)]))
        #expect(report == CardioIngestReport(inserted: 1, filled: 0))

        let row = try #require(rows(db).first)
        #expect(row.kind == CardioImport.walk)
        #expect(row.distanceM == 4200)
        #expect(row.durationMin == 50)
        #expect(row.avgHr == 112)
        #expect(row.elevationM == 86)
        #expect(row.fromHealthkit == true)
        // TOTAL energy is active plus resting over the bout's OWN window:
        // 210 + (1.2 × 50) = 270. Not the day's basal, not a guess.
        #expect(row.totalKcal == 270)
        // `created_at` is the bout's start, not the instant of the import — the
        // field the duplicate rule reads next time and the export prints as
        // `start_time`. 07:00 UTC, four hours before `now`.
        #expect(row.createdAt == calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 7)))
        // The write went through `addCardio`, so the push is queued and the
        // pre-migration `kcal` column carries the active figure.
        #expect(row.kcal == 210)
    }

    @Test("a lifting workout is never filed as cardio")
    func skipsLifting() async throws {
        let db = try store()
        var lift = bout(hour: 18, minutes: 60)
        lift.isLifting = true
        lift.cardioKind = nil
        let report = try await ingest(db, Wrist(bouts: [lift]))
        #expect(report.isEmpty)
        #expect(try rows(db).isEmpty)
    }

    @Test("every mapped kind comes in, not just walks and runs")
    func ingestsEveryMappedKind() async throws {
        let db = try store()
        let kinds = [CardioImport.walk, CardioImport.run, CardioImport.cycling,
                     CardioImport.rowing, CardioImport.elliptical, CardioImport.hiit]
        let bouts = kinds.enumerated().map { bout(hour: 6 + $0.offset, minutes: 30, kind: $0.element) }
        let report = try await ingest(db, Wrist(bouts: bouts))
        #expect(report.inserted == kinds.count)
        #expect(Set(try rows(db).map(\.kind)) == Set(kinds))
    }

    @Test("running the pass twice does not log the walk twice")
    func isIdempotent() async throws {
        let db = try store()
        let reader = Wrist(bouts: [bout(hour: 7, minutes: 50)])
        _ = try await ingest(db, reader)
        let second = try await ingest(db, reader)
        // Nothing inserted AND nothing filled: the second pass found the row it
        // wrote, merged it against itself, saw no change and did not write. A
        // launch on a quiet day costs one read and no rows.
        #expect(second.isEmpty)
        #expect(try rows(db).count == 1)
    }

    // MARK: - Merging

    @Test("a hand-typed bout keeps every figure it has and gains only the blanks")
    func fillsBlanksWithoutOverwriting() async throws {
        let db = try store()
        // The treadmill case: a console's own distance, typed at 21:00 for a
        // walk done that morning, with no heart rate and no ascent because no
        // console shows them.
        let typed = CardioLogRow(
            id: "c1", userId: user, date: today, kind: CardioImport.walk,
            distanceM: 5000, durationMin: 50, kcal: 300,
            createdAt: calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 21)),
            activeKcal: 300
        )
        try db.addCardio(typed)

        let report = try await ingest(db, Wrist(bouts: [bout(hour: 7, minutes: 50)]))
        #expect(report == CardioIngestReport(inserted: 0, filled: 1))

        let row = try #require(rows(db).first)
        #expect(row.id == "c1")
        // The typed figures stand. Health says 4200 m and 210 kcal; the person
        // read 5000 m and 300 kcal off the console and that is the number they
        // trust. An unattended process does not get to overrule them.
        #expect(row.distanceM == 5000)
        #expect(row.activeKcal == 300)
        #expect(row.durationMin == 50)
        // The blanks are filled — the figures nobody types.
        #expect(row.avgHr == 112)
        #expect(row.elevationM == 86)
        #expect(row.totalKcal == 270)
        // And it is still a hand-typed row. Flipping the provenance would make
        // the export print a 21:00 insertion instant as the bout's start.
        #expect(row.fromHealthkit != true)
    }

    @Test("a pre-migration row's active figure in `kcal` alone is not treated as a blank")
    func readsLegacyKcalAsActive() async throws {
        let db = try store()
        // `active_kcal` arrived later than `kcal`; a row written before it
        // carries the active figure in `kcal` and nothing in `active_kcal`.
        // Reading only `active_kcal` would see a blank and fill it from Health
        // — overwriting by the back door, which is the one thing this path
        // must not do.
        let legacy = CardioLogRow(
            id: "c1", userId: user, date: today, kind: CardioImport.walk,
            distanceM: 5000, durationMin: 50, kcal: 333,
            createdAt: calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 21))
        )
        try db.addCardio(legacy)

        _ = try await ingest(db, Wrist(bouts: [bout(hour: 7, minutes: 50)]))
        let row = try #require(rows(db).first)
        #expect(row.activeKcal == 333)
        #expect(row.kcal == 333)
    }

    @Test("a matched row Health can add nothing to is not rewritten")
    func writesNothingWhenThereIsNothingToAdd() async throws {
        let db = try store()
        let complete = CardioLogRow(
            id: "c1", userId: user, date: today, kind: CardioImport.walk,
            distanceM: 5000, durationMin: 50, kcal: 300, fromHealthkit: true,
            createdAt: calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 7)),
            activeKcal: 300, totalKcal: 360, avgHr: 130, elevationM: 100
        )
        try db.addCardio(complete)

        let report = try await ingest(db, Wrist(bouts: [bout(hour: 7, minutes: 50)]))
        #expect(report.isEmpty)
        let row = try #require(rows(db).first)
        #expect(row.avgHr == 130)
        #expect(row.elevationM == 100)
    }

    @Test("two walks the same morning map one to one, closest start wins")
    func matchesTheNearerBout() async throws {
        let db = try store()
        let reader = Wrist(bouts: [bout(hour: 7, minutes: 30), bout(hour: 11, minutes: 30)])
        #expect(try await ingest(db, reader).inserted == 2)
        // And a second pass still sees two, not four: each stored start is
        // within the five-minute window of exactly one incoming bout.
        #expect(try await ingest(db, reader).isEmpty)
        #expect(try rows(db).count == 2)
    }

    // MARK: - The key (W1)

    @Test("the same HKWorkout ingested five times is one row")
    func theKeyEndsTheDuplicate() async throws {
        let db = try store()
        let id = UUID()
        // Five passes over a bout whose `created_at` DID NOT SURVIVE. This is
        // the shape that produced 23 copies of one walk: the precise branch
        // skips a row with no start, the fuzzy branch only looks at hand-typed
        // rows, so before the key every pass inserted.
        for pass in 0..<5 {
            let report = try await ingest(db, Wrist(bouts: [bout(hour: 7, minutes: 50, uuid: id)]))
            #expect(report.inserted == (pass == 0 ? 1 : 0))
            // And the start is wiped after each pass, so no later pass can be
            // rescued by the window.
            try await db.writer.write { conn in
                try conn.execute(sql: "UPDATE cardio_logs SET created_at = NULL")
            }
        }
        #expect(try rows(db).count == 1)
    }

    /// The defect the founder reported: an auto-logged walk showing the time
    /// the app was opened. The row is matched by its uuid on every pass, so no
    /// duplicate appears — and until this test the pass that matched it copied
    /// the figures and left the wrong start exactly where it was.
    @Test("an imported row whose start became the import instant is repaired")
    func repairsADriftedStart() async throws {
        let db = try store()
        let id = UUID()
        #expect(try await ingest(db, Wrist(bouts: [bout(hour: 7, minutes: 50, uuid: id)])).inserted == 1)

        // 22:47 — the moment of an evening launch, standing where the bout's
        // 07:00 start belongs. This is what a row pulled back from the web era
        // or written before the start rule existed actually holds.
        let wrong = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 22, minute: 47))!
        try await db.writer.write { conn in
            try conn.execute(sql: "UPDATE cardio_logs SET created_at = ?", arguments: [wrong])
        }

        // Nothing is INSERTED (the key matched) and nothing is FILLED (Health
        // could add no figure the row did not already have) — the repair is not
        // news the toast may claim.
        let report = try await ingest(db, Wrist(bouts: [bout(hour: 7, minutes: 50, uuid: id)]))
        #expect(report.isEmpty)

        let stored = try rows(db)
        #expect(stored.count == 1)
        let row = try #require(stored.first)
        let start = try #require(row.createdAt)
        #expect(abs(start.timeIntervalSince(bout(hour: 7, minutes: 50).start)) < 1,
                "the bout's own start, not the instant of the import")
    }

    /// The other half of the rule. A hand-typed row's `created_at` is when it
    /// was typed; a bout that matches it by the fuzzy window must not stamp a
    /// start onto a row whose provenance says it has none.
    @Test("a hand-typed row keeps the moment it was typed")
    func doesNotRestampAManualRow() async throws {
        let db = try store()
        let typedAt = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 21))!
        try db.addCardio(CardioLogRow(
            id: "m1", userId: user, date: today, kind: CardioImport.walk,
            distanceM: 4200, durationMin: 50, kcal: 210, fromHealthkit: false,
            createdAt: typedAt, activeKcal: 210, totalKcal: 270, avgHr: 112, elevationM: 86
        ))

        _ = try await ingest(db, Wrist(bouts: [bout(hour: 7, minutes: 50)]))

        let row = try #require(rows(db).first)
        #expect(row.id == "m1")
        #expect(row.createdAt == typedAt)
    }

    @Test("a pre-migration row matches by window and gains the key")
    func adoptsTheKey() async throws {
        let db = try store()
        // Imported before `hk_uuid` existed: right provenance, right start, no
        // key. The window is what finds it, and finding it is what retires the
        // window for this row.
        try db.addCardio(CardioLogRow(
            id: "c1", userId: user, date: today, kind: CardioImport.walk,
            distanceM: 4200, durationMin: 50, kcal: 210, fromHealthkit: true,
            createdAt: calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 7)),
            activeKcal: 210, totalKcal: 270, avgHr: 112, elevationM: 86
        ))

        let id = UUID()
        let report = try await ingest(db, Wrist(bouts: [bout(hour: 7, minutes: 50, uuid: id)]))
        // Nothing INSERTED and nothing FILLED: Health could add no figure this
        // row did not already have, and stamping a key nobody can see on a
        // screen is not news the toast may claim.
        #expect(report.isEmpty)

        let row = try #require(rows(db).first)
        #expect(row.id == "c1")
        #expect(row.hkUuid == id.uuidString.lowercased())
    }

    @Test("a hand-typed bout three minutes off still matches by window, and is not re-flagged")
    func handTypedStillMatchesByWindow() async throws {
        let db = try store()
        // Typed at 21:00 for a walk done at 07:00 — `created_at` on this row is
        // an insertion instant, so only the fuzzy duration rule can see it.
        // Three minutes of difference in the duration, well inside the window.
        try db.addCardio(CardioLogRow(
            id: "c1", userId: user, date: today, kind: CardioImport.walk,
            distanceM: 5000, durationMin: 47, kcal: 300,
            createdAt: calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 21)),
            activeKcal: 300
        ))

        let id = UUID()
        let report = try await ingest(db, Wrist(bouts: [bout(hour: 7, minutes: 50, uuid: id)]))
        #expect(report == CardioIngestReport(inserted: 0, filled: 1))

        let row = try #require(rows(db).first)
        #expect(row.id == "c1")
        // The typed figures stand and the provenance is untouched — the row is
        // still one a person wrote, and the export must keep printing 21:00.
        #expect(row.distanceM == 5000)
        #expect(row.durationMin == 47)
        #expect(row.fromHealthkit != true)
        // But it carries the key now, so the next pass matches it outright.
        #expect(row.hkUuid == id.uuidString.lowercased())
        #expect(try await ingest(db, Wrist(bouts: [bout(hour: 7, minutes: 50, uuid: id)])).isEmpty)
        #expect(try rows(db).count == 1)
    }

    @Test("a second bout never steals a key the first one stamped")
    func theKeyIsStampedOnce() async throws {
        let db = try store()
        // One hand-typed 50-minute walk and TWO Health bouts of the same
        // length. Both fuzzy-match the same row; if the second overwrote the
        // first's key the row would be rewritten — and toasted — on every
        // launch for the rest of the day.
        try db.addCardio(CardioLogRow(
            id: "c1", userId: user, date: today, kind: CardioImport.walk,
            distanceM: 5000, durationMin: 50, kcal: 300,
            createdAt: calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 21)),
            activeKcal: 300, totalKcal: 400, avgHr: 130, elevationM: 40
        ))
        let first = UUID()
        let reader = Wrist(bouts: [
            bout(hour: 7, minutes: 50, uuid: first),
            bout(hour: 17, minutes: 50, uuid: UUID()),
        ])
        _ = try await ingest(db, reader)
        let keyed = try rows(db).first { $0.id == "c1" }
        #expect(keyed?.hkUuid == first.uuidString.lowercased())
        // And a second pass writes nothing at all.
        #expect(try await ingest(db, reader).isEmpty)
    }

    @Test("a bout that started on the previous day is not filed under this one")
    func theDayIsTheDayItStartedIn() async throws {
        let db = try store()
        // 23:40 on the 3rd, running to 00:20 on the 4th. `reader.workouts` has
        // no `.strictStartDate`, so this bout is returned by BOTH days' queries
        // — and used to be inserted under both, two rows for one walk, on two
        // dates no same-day rule can compare.
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 23, minute: 40))!
        let overnight = WorkoutSample(
            uuid: UUID(), start: start, end: start.addingTimeInterval(40 * 60),
            isLifting: false, cardioKind: CardioImport.walk, distanceM: 3000, activeKcal: 150
        )
        #expect(try await ingest(db, Wrist(bouts: [overnight])).isEmpty)
        #expect(try rows(db).isEmpty)
    }

    // MARK: - The store being unavailable

    @Test("no Health store is an empty report, never a throw")
    func unavailableStoreIsSilent() async throws {
        let db = try store()
        let report = try await ingest(db, Wrist(isAvailable: false, bouts: [bout(hour: 7, minutes: 50)]))
        #expect(report.isEmpty)
        #expect(try rows(db).isEmpty)
    }
}

@Suite("The merge rule: an unattended process only ever adds")
struct CardioMergeTests {

    @Test("every stored value wins, every stored blank is filled")
    func storedWins() {
        let stored = CardioImport.Fields(distanceM: 5000, durationMin: 50, activeKcal: 300)
        let incoming = CardioImport.Fields(
            distanceM: 4200, durationMin: 48, activeKcal: 210,
            totalKcal: 270, avgHr: 112, elevationM: 86
        )
        #expect(CardioImport.merge(stored: stored, incoming: incoming) == CardioImport.Fields(
            distanceM: 5000, durationMin: 50, activeKcal: 300,
            totalKcal: 270, avgHr: 112, elevationM: 86
        ))
    }

    @Test("merging a row against itself changes nothing")
    func isIdempotent() {
        let row = CardioImport.Fields(
            distanceM: 4200, durationMin: 50, activeKcal: 210,
            totalKcal: 270, avgHr: 112, elevationM: 86, inclinePct: 3
        )
        #expect(CardioImport.merge(stored: row, incoming: row) == row)
    }

    @Test("an incline nobody can read from Health survives the merge")
    func keepsIncline() {
        // HealthKit has no incline metric for a walk, so the ingest never
        // supplies one. It is in `Fields` so a merge stays a whole-row
        // replacement the caller cannot accidentally narrow — the shape of bug
        // where a treadmill's 3% gradient disappears on the next launch.
        let stored = CardioImport.Fields(durationMin: 30, inclinePct: 3)
        let merged = CardioImport.merge(stored: stored, incoming: CardioImport.Fields(avgHr: 120))
        #expect(merged.inclinePct == 3)
        #expect(merged.avgHr == 120)
    }

    @Test("a zero is a value, not a blank")
    func zeroIsNotMissing() {
        // A flat walk climbed 0 m and that is a fact. `??` treats only nil as
        // absent, which is the behaviour wanted — a `0` coalesced away would
        // let Health overwrite a measured flat with its own estimate.
        let merged = CardioImport.merge(
            stored: CardioImport.Fields(elevationM: 0),
            incoming: CardioImport.Fields(elevationM: 86)
        )
        #expect(merged.elevationM == 0)
    }
}

@Suite("One physical bout is one row: the v27 collapse")
struct CardioDuplicateSweepTests {

    private let user = "u1"
    private let day = "2026-09-04"
    private let start = Date(timeIntervalSince1970: 1_788_508_800)

    private func row(
        _ id: String, kind: String = CardioImport.walk, createdAt: Date?,
        durationMin: Double? = 50, distanceM: Double? = 4200,
        avgHr: Double? = nil, totalKcal: Double? = nil, userId: String = "u1"
    ) -> CardioLogRow {
        CardioLogRow(
            id: id, userId: userId, date: "2026-09-04", kind: kind,
            distanceM: distanceM, durationMin: durationMin, fromHealthkit: true,
            createdAt: createdAt, totalKcal: totalKcal, avgHr: avgHr
        )
    }

    private func sweep(_ rows: [CardioLogRow]) throws -> AppDatabase {
        let db = try AppDatabase.inMemory(deviceId: "sweep")
        try db.writer.write { conn in
            for var r in rows { try r.insert(conn) }
            try AppDatabase.collapseCardioDuplicates(conn)
        }
        return db
    }

    private func ids(_ db: AppDatabase) throws -> [String] {
        try db.writer.read { try CardioLogRow.order(Column("id")).fetchAll($0).map(\.id) }
    }

    @Test("twenty-three copies of one walk collapse to one")
    func collapsesTheExportAnomaly() throws {
        // The shape `WeeklyExportBuilder` found on a Friday and has deduped at
        // render time ever since. Identical on every field the key reads.
        let db = try sweep((0..<23).map { row("c\($0)", createdAt: start) })
        #expect(try ids(db) == ["c0"])
    }

    @Test("the richest row survives, not the first")
    func keepsTheMostMeasured() throws {
        // The duplicates are NOT identical: an early import holds the heart
        // rate, a later pass gained a total energy. Keeping the emptiest would
        // lose a measurement nothing can recover.
        let db = try sweep([
            row("a", createdAt: start),
            row("b", createdAt: start, avgHr: 112, totalKcal: 270),
            row("c", createdAt: start, avgHr: 112),
        ])
        #expect(try ids(db) == ["b"])
    }

    @Test("a tie breaks on the lowest id — the same way the SQL file breaks it")
    func tiesBreakDeterministically() throws {
        // A one-off server-side pass ran the identical collapse for
        // rows no device will open again. Two rules that disagree about the
        // survivor delete each other's keeper.
        let db = try sweep([
            row("b2", createdAt: start, avgHr: 112),
            row("a1", createdAt: start, avgHr: 112),
        ])
        #expect(try ids(db) == ["a1"])
    }

    @Test("the losers are deleted THROUGH the outbox, or they come straight back")
    func queuesTheServerDeletes() throws {
        // `cardio_logs` pulls on a date window. A row removed locally and left
        // on the server returns on the next sync, and the migration looks like
        // it never ran.
        let db = try sweep([row("a", createdAt: start), row("b", createdAt: start)])
        let deletes = try db.pendingOutbox()
            .filter { $0.kind == SyncKind.rowDelete }
            .map { try OnyxJSON.decoder.decode(RowDeleteRef.self, from: $0.payload) }
        #expect(deletes == [RowDeleteRef(table: "cardio_logs", key: ["id": "b"])])
    }

    @Test("a row with no start is never collapsed")
    func nullStartsAreLeftAlone() throws {
        // `created_at` is nullable with no default, and a key built from three
        // absences is the same key for every such row — a Monday cycle and a
        // Friday swim would fold into one another. The export skips them for
        // the same reason and says so in its own comment.
        let db = try sweep([
            row("a", kind: CardioImport.cycling, createdAt: nil, durationMin: nil, distanceM: nil),
            row("b", kind: CardioImport.cycling, createdAt: nil, durationMin: nil, distanceM: nil),
        ])
        #expect(try ids(db) == ["a", "b"])
    }

    @Test("two genuinely different bouts survive, and two users never collide")
    func keepsWhatIsNotADuplicate() throws {
        let db = try sweep([
            row("a", createdAt: start),
            row("b", createdAt: start.addingTimeInterval(3600)),
            row("c", kind: CardioImport.run, createdAt: start),
            row("d", createdAt: start, distanceM: 9000),
            // Same bout key, different account. One store holds one user today,
            // but the key carries `user_id` so it cannot start mattering later.
            row("e", createdAt: start, userId: "u2"),
        ])
        #expect(try ids(db) == ["a", "b", "c", "d", "e"])
    }

    @Test("running it twice changes nothing the second time")
    func isIdempotent() throws {
        let db = try sweep([row("a", createdAt: start), row("b", createdAt: start)])
        try db.writer.write { try AppDatabase.collapseCardioDuplicates($0) }
        #expect(try ids(db) == ["a"])
    }
}

// MARK: - Overhaul C2 · the treadmill relabel

extension CardioIngestTests {

    @Test("an indoor walk already filed as a walk is relabelled a treadmill, not duplicated")
    func relabelsKeyedWalk() async throws {
        let db = try store()
        let id = UUID()
        // The row an older build filed: Health said `.walking`, nobody read the
        // indoor key.
        _ = try await ingest(db, Wrist(bouts: [bout(hour: 7, minutes: 30, uuid: id)]))
        #expect(try rows(db).map(\.kind) == [CardioImport.walk])
        // This build reads the key: the same workout is a treadmill.
        _ = try await ingest(db, Wrist(bouts: [bout(hour: 7, minutes: 30, kind: CardioImport.treadmill, uuid: id)]))
        #expect(try rows(db).map(\.kind) == [CardioImport.treadmill])
    }

    @Test("a pre-uuid imported walk matches an indoor bout by its start and is relabelled once")
    func relabelsUnkeyedImport() async throws {
        let db = try store()
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 7))!
        try db.addCardio(CardioLogRow(id: "old", userId: user, date: today, kind: CardioImport.walk,
                                      durationMin: 30, fromHealthkit: true, createdAt: start))
        let reader = Wrist(bouts: [bout(hour: 7, minutes: 30, kind: CardioImport.treadmill)])
        _ = try await ingest(db, reader)
        let after = try rows(db)
        #expect(after.count == 1)
        #expect(after.first?.kind == CardioImport.treadmill)
        // Idempotent: the second pass writes nothing.
        #expect(try await ingest(db, reader).isEmpty)
    }

    @Test("a hand-typed walk keeps the athlete's own word")
    func handTypedWalkIsNotRelabelled() async throws {
        let db = try store()
        try db.addCardio(CardioLogRow(id: "typed", userId: user, date: today, kind: CardioImport.walk,
                                      durationMin: 30, fromHealthkit: false, createdAt: now))
        _ = try await ingest(db, Wrist(bouts: [bout(hour: 7, minutes: 30, kind: CardioImport.treadmill)]))
        #expect(try rows(db).first { $0.id == "typed" }?.kind == CardioImport.walk)
        #expect(try rows(db).count == 1, "matched, not duplicated")
    }
}

// MARK: - Overhaul C2 · the one-time treadmill door

extension CardioIngestTests {

    /// The first ordinary sync after the upgrade walks back 90 days ONCE, so
    /// every indoor walk an older build filed as `walk` is relabelled; the flag
    /// then closes the door and the next sync is the usual two days.
    @Test("the first sync after the upgrade relabels 90 days of walks, once")
    func treadmillDoorRunsOnce() async throws {
        let db = try store()
        let key = "treadmill-door-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let id = UUID()
        // A bout a month back, filed as a walk by the old reader.
        let old = calendar.date(byAdding: .day, value: -30, to: now)!
        var walk = bout(hour: 7, minutes: 30, uuid: id)
        walk.start = old
        walk.end = old.addingTimeInterval(30 * 60)
        try db.addCardio(CardioLogRow(
            id: "old", userId: user, date: LogicalDayISO.string(old, calendar: calendar), kind: CardioImport.walk,
            durationMin: 30, fromHealthkit: true, createdAt: old, hkUuid: id.uuidString.lowercased()))
        var indoor = walk
        indoor.cardioKind = CardioImport.treadmill
        let sync = HealthSync(database: db, reader: Wrist(bouts: [indoor]), userId: user)

        _ = try await sync.syncCardioBouts(now: now, calendar: calendar, days: 2, doorKey: key)
        let rows = try db.cardioRows(userId: user, date: LogicalDayISO.string(old, calendar: calendar))
        #expect(rows.map(\.kind) == [CardioImport.treadmill])
        #expect(UserDefaults.standard.bool(forKey: key))

        // A second walk on that old day stays untouched now the door is shut.
        try db.addCardio(CardioLogRow(
            id: "old2", userId: user, date: LogicalDayISO.string(old, calendar: calendar), kind: CardioImport.walk,
            durationMin: 30, fromHealthkit: true, createdAt: old.addingTimeInterval(3 * 3600), hkUuid: "other"))
        var second = indoor
        second.uuid = UUID(uuidString: "00000000-0000-0000-0000-0000000000AB")!
        _ = try await HealthSync(database: db, reader: Wrist(bouts: [second]), userId: user)
            .syncCardioBouts(now: now, calendar: calendar, days: 2, doorKey: key)
        #expect(try db.cardioRows(userId: user, date: LogicalDayISO.string(old, calendar: calendar))
            .first { $0.id == "old2" }?.kind == CardioImport.walk)
    }
}

extension CardioIngestTests {

    /// Review fixes: the door's extra days never re-import, and a pass Health
    /// answered with nothing leaves the door open for the next one.
    @Test("the treadmill door neither re-imports old bouts nor closes on a silent Health")
    func treadmillDoorIsCareful() async throws {
        let db = try store()
        let key = "treadmill-door-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let old = calendar.date(byAdding: .day, value: -30, to: now)!
        let oldDay = LogicalDayISO.string(old, calendar: calendar)
        try db.addCardio(CardioLogRow(
            id: "kept", userId: user, date: oldDay, kind: CardioImport.walk,
            durationMin: 30, fromHealthkit: true, createdAt: old, hkUuid: "kept-uuid"))

        // Health answers nothing: no relabel, and the door stays open.
        _ = try await HealthSync(database: db, reader: Wrist(bouts: []), userId: user)
            .syncCardioBouts(now: now, calendar: calendar, days: 2, doorKey: key)
        #expect(!UserDefaults.standard.bool(forKey: key))

        // Health answers with a bout the athlete had deleted a month ago: it
        // is NOT re-imported by the door's extra days.
        var deleted = bout(hour: 7, minutes: 30)
        deleted.start = old.addingTimeInterval(5 * 3600)
        deleted.end = deleted.start.addingTimeInterval(1800)
        _ = try await HealthSync(database: db, reader: Wrist(bouts: [deleted]), userId: user)
            .syncCardioBouts(now: now, calendar: calendar, days: 2, doorKey: key)
        #expect(try db.cardioRows(userId: user, date: oldDay).map(\.id) == ["kept"])
        #expect(UserDefaults.standard.bool(forKey: key))
    }

    @Test("with no imported walk on the ledger the door closes without a scan")
    func treadmillDoorClosesWhenNothingToDo() async throws {
        let db = try store()
        let key = "treadmill-door-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        _ = try await HealthSync(database: db, reader: Wrist(bouts: []), userId: user)
            .syncCardioBouts(now: now, calendar: calendar, days: 2, doorKey: key)
        #expect(UserDefaults.standard.bool(forKey: key))
    }
}
