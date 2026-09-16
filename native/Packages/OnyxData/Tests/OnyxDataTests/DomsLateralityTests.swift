import Foundation
import GRDB
import Testing
@testable import OnyxCore
@testable import OnyxData

/// The store half of laterality: a left glute and a right glute as two rows
/// that coexist, and every reader downstream of them.
///
/// ── THE THING THAT WAS ACTUALLY MISSING ─────────────────────────────────────
/// The atlas has drawn two paths per bilateral muscle since it was first drawn.
/// `OnyxAtlasHit` has always found which of the two a finger was in. The words
/// existed (`DomsMuscles.sides`), the export grammar existed
/// (`muscle[/subRegion][@L|@R]`), and the `ExportDoms` fields existed. Only the
/// STORAGE was missing: one row per `(user_id, date, muscle_group)` meant a left
/// rating and a right rating collided, so there was no point in any of the rest.
/// These tests are about the key, and about the two things that must not have
/// moved when it widened — the fold, and a legacy row's meaning.
@Suite("Soreness laterality — the store")
struct DomsLateralityStoreTests {

    private let user = "u1"
    private let date = "2026-09-16"

    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    private func rows(_ db: AppDatabase) throws -> [DomsLogRow] {
        try db.read { try DomsLogRow.order(Column("muscle_group"), Column("side")).fetchAll($0) }
    }

    @Test("a left rating and a right rating are two rows on one day, for one muscle")
    func sidesCoexist() throws {
        let db = try store()
        try db.setDoms(userId: user, date: date, muscleGroup: "Glutes", severity: 3, side: .right)
        try db.setDoms(userId: user, date: date, muscleGroup: "Glutes", severity: 1, side: .left)

        let got = try rows(db)
        #expect(got.count == 2)
        #expect(Set(got.map(\.side)) == ["left", "right"])
        #expect(got.first { $0.side == "right" }?.severity == 3)
        #expect(got.first { $0.side == "left" }?.severity == 1)
        // Distinct ids, so the outbox pushes two rows rather than one twice.
        #expect(Set(got.map(\.id)).count == 2)
    }

    @Test("both stores NULL, and re-rating the same side updates in place")
    func bothIsAbsence() throws {
        let db = try store()
        try db.setDoms(userId: user, date: date, muscleGroup: "Quads", severity: 2)
        var got = try rows(db)
        #expect(got.count == 1)
        // NULL, not the word: absence is the pre-W9 meaning of this column, and
        // it is what keeps the push body — and so the export token — byte
        // identical to what every build before this one sent.
        #expect(got[0].side == nil && got[0].subRegion == nil)

        let firstId = got[0].id
        try db.setDoms(userId: user, date: date, muscleGroup: "Quads", severity: 3)
        got = try rows(db)
        #expect(got.count == 1)
        #expect(got[0].id == firstId && got[0].severity == 3)

        // …and a SIDED rating of the same muscle does not overwrite it.
        try db.setDoms(userId: user, date: date, muscleGroup: "Quads", severity: 1, side: .left)
        #expect(try rows(db).count == 2)
    }

    @Test("a legacy row with side = nil is found and updated, not duplicated")
    func legacyRowsReadAsBoth() throws {
        let db = try store()
        // A row as every build before W9 wrote it: no side, no sub-region.
        try db.writer.write { conn in
            try DomsLogRow(id: "legacy", userId: user, date: date, muscleGroup: "Chest", severity: 1)
                .insert(conn)
        }
        // The default side is `.both`, and `Column("side") == nil` is `IS NULL`
        // in GRDB — which is what makes the legacy row the row this finds. A
        // naive `side = 'both'` comparison matches nothing and mints a second.
        try db.setDoms(userId: user, date: date, muscleGroup: "Chest", severity: 3)

        let got = try rows(db)
        #expect(got.count == 1)
        #expect(got[0].id == "legacy" && got[0].severity == 3 && got[0].side == nil)
        #expect(BodySide(stored: got[0].side) == .both)
    }

    @Test("a sub-region is part of the key, and the whole muscle is still its own row")
    func subRegionsAreKeyed() throws {
        let db = try store()
        try db.setDoms(userId: user, date: date, muscleGroup: "Back", severity: 1)
        try db.setDoms(userId: user, date: date, muscleGroup: "Back", severity: 3, subRegion: "Erectors")
        try db.setDoms(userId: user, date: date, muscleGroup: "Back", severity: 2, side: .left, subRegion: "Lats")
        #expect(try rows(db).count == 3)
    }

    @Test("the scorer's fold is unchanged: max within a muscle, mean across muscles")
    func theBatteryDoesNotMove() throws {
        let whole = try store()
        try whole.setDoms(userId: user, date: date, muscleGroup: "Quads", severity: 3)
        try whole.setDoms(userId: user, date: date, muscleGroup: "Chest", severity: 1)

        let split = try store()
        try split.setDoms(userId: user, date: date, muscleGroup: "Quads", severity: 3, side: .left)
        try split.setDoms(userId: user, date: date, muscleGroup: "Quads", severity: 1, side: .right)
        try split.setDoms(userId: user, date: date, muscleGroup: "Chest", severity: 1)

        // Two rows for one muscle must weigh exactly what one row weighed. If
        // this moves, every battery golden vector moves with it and the wave is
        // wrong (W9 self-check).
        let a = AppDatabase.foldDomsSeverity(try rows(whole))
        let b = AppDatabase.foldDomsSeverity(try rows(split))
        #expect(a == 2)
        #expect(a == b)
    }

    @Test("the push carries the widened conflict target")
    func conflictTargetWidened() {
        // PostgREST's `on_conflict` is a COLUMN LIST, and the server index it
        // resolves against is `(user_id, date, muscle_group, side, sub_region)
        // NULLS NOT DISTINCT` — `docs/sql/w9-doms-laterality.sql`. The old
        // three-column target would reject a one-sided row as a duplicate of
        // the whole-muscle one.
        let table = MirrorCatalogue.tables.first { $0.name == "doms_logs" }
        #expect(table?.conflict == "user_id,date,muscle_group,side,sub_region")
    }
}

/// The export's first native construction site.
@Suite("Soreness laterality — the export")
struct DomsLateralityExportTests {

    private let user = "u1"
    private let weekStart = "2026-09-14"

    private func input(_ write: (AppDatabase) throws -> Void) throws -> WeeklyExportInput {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        try write(db)
        return try WeeklyExportBuilder(database: db, userId: user, timeZone: TimeZone(identifier: "UTC")!)
            .input(weekStart: weekStart, today: weekStart)
    }

    @Test("a one-sided rating reaches the document as @L or @R")
    func sidesReachTheDocument() throws {
        let got = try input { db in
            try db.setDoms(userId: user, date: weekStart, muscleGroup: "Glutes", severity: 3, side: .right)
        }
        let row = try #require(got.doms.first)
        #expect(row.side == "right" && row.subRegion == nil)
        #expect(WeeklyExport.build(got).contains("Glutes@R 3"))
    }

    @Test("a bilateral rating renders the bare muscle name, as v1 did")
    func bilateralIsUnchanged() throws {
        let got = try input { db in
            try db.setDoms(userId: user, date: weekStart, muscleGroup: "Quads", severity: 2)
        }
        let row = try #require(got.doms.first)
        // nil, NOT "both". The builder passes the column through rather than
        // normalising it, which is the whole reason the three v1 export goldens
        // still pass untouched.
        #expect(row.side == nil && row.subRegion == nil)
        let document = WeeklyExport.build(got)
        #expect(document.contains("Quads 2"))
        #expect(!document.contains("Quads@"))
        #expect(!document.contains("Quads/"))
    }

    @Test("a left and a right rating of one muscle both survive the sort")
    func bothSidesSurviveTheStableSort() throws {
        let got = try input { db in
            try db.setDoms(userId: user, date: weekStart, muscleGroup: "Glutes", severity: 3, side: .right)
            try db.setDoms(userId: user, date: weekStart, muscleGroup: "Glutes", severity: 1, side: .left)
        }
        // Two rows, ordered deterministically. `(date, muscle)` alone left them
        // comparing EQUAL, so the document's order would have been whatever the
        // fetch returned — the exact non-determinism a golden document exists
        // to catch, arriving as a flake instead of a failure.
        #expect(got.doms.map { "\($0.muscle)\($0.side ?? "")" } == ["Glutesleft", "Glutesright"])
        let document = WeeklyExport.build(got)
        #expect(document.contains("Glutes@L 1"))
        #expect(document.contains("Glutes@R 3"))
    }
}
