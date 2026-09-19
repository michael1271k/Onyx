import Foundation
import GRDB
import Testing
@testable import OnyxCore
@testable import OnyxData

/// What `v32.onyxWire` is for.
///
/// ── THE RENAME THAT COULD HAVE SPLIT EVERY HISTORY ──────────────────────────
/// The predecessor web app's name was a stored VALUE in two places: the current
/// era in `plan_phases.era`, and the prefix on every exercise id the logger
/// stamps. Renaming the prefix in the stamping function alone would have filed
/// every set logged from 7.0.0 under a second identity — the exact split
/// `ExerciseIndex`'s header exists to prevent — so the migration moves the four
/// places an id is stored at once, in one transaction.
///
/// The case that matters most is the one a table-only migration gets wrong: an
/// event-backed session. The projection and the append log are two copies of
/// the same id, and any edit rebuilds the projection from the log. Migrate one
/// and not the other and the session comes back half under each name. So the
/// central test here is not "the id changed" — it is **the fold agrees with the
/// table, before and after**.
@Suite("Onyx wire — the predecessor's name leaves the data")
struct OnyxWireMigrationTests {

    private func database() throws -> AppDatabase {
        try AppDatabase.inMemory(deviceId: "d1")
    }

    /// The predecessor's stamp, spelled the only way this repository still
    /// can: assembled, because the brand itself is gone from every byte of it
    /// (sprint decision 19). `legacy("hack-squat")` is one legacy id.
    private func legacy(_ body: String) -> String { "port5-" + body }

    private func migrate(_ db: AppDatabase) throws {
        try db.writer.write { try AppDatabase.adoptOnyxWire($0) }
    }

    private func sets(in db: AppDatabase) throws -> [WorkoutSet] {
        try db.writer.read { conn in
            try WorkoutSet.order(Column("set_index")).fetchAll(conn)
        }
    }

    private func seedSession(_ db: AppDatabase) throws {
        try db.writer.write { conn in
            try WorkoutSession(id: "s1", userId: "u1", dayKey: "legs_a", date: "2026-09-07")
                .insert(conn)
        }
    }

    // MARK: - The fold, before and after

    /// The golden the wave was asked for, and the one with teeth.
    ///
    /// Every field of every set is compared, not just the id: the rename is a
    /// PREFIX swap on one column and must leave load, reps, index, type and
    /// order untouched. Then the session is reprojected from its own log — the
    /// gesture any edit performs — and the table must come back the same. A
    /// migration that moved the table and not the log passes the first half of
    /// this test and fails the second.
    @Test("the fold agrees with the table, before and after the rewrite")
    func foldSurvivesTheRewrite() throws {
        let db = try database()
        try seedSession(db)
        for (i, movement) in ["hack-squat", "leg-press", "seated-leg-curl"].enumerated() {
            _ = try db.appendSet(sessionId: "s1", SetSnapshot(
                exerciseId: legacy(movement), setIndex: i + 1,
                weightKg: 60 + Double(i) * 10, reps: 8 + i, setType: "normal"
            ))
        }

        let before = try sets(in: db)
        #expect(before.count == 3)
        #expect(before.allSatisfy { $0.exerciseId.hasPrefix("port5-") })

        try migrate(db)

        let after = try sets(in: db)
        #expect(after.map(\.exerciseId) == ["onyx-hack-squat", "onyx-leg-press", "onyx-seated-leg-curl"])
        // Everything that is not the stamp is byte-identical.
        for (old, new) in zip(before, after) {
            #expect(new.exerciseId == "onyx-" + old.exerciseId.dropFirst("port5-".count))
            #expect(new.setIndex == old.setIndex)
            #expect(new.weightKg == old.weightKg)
            #expect(new.reps == old.reps)
            #expect(new.setType == old.setType)
            #expect(new.id == old.id)
        }

        // The half a table-only migration loses: rebuild from the log.
        try db.reprojectAll()
        #expect(try sets(in: db).map(\.exerciseId) == after.map(\.exerciseId))
    }

    /// ── THE SHAPE A REAL DEVICE ACTUALLY HAS ──────────────────────────────
    /// `foldSurvivesTheRewrite` seeds sets and no catalogue; `migratesTheCatalogue`
    /// seeds a catalogue and no sets. A phone has BOTH, and that is the case
    /// where the migration's two halves interact: the rename runs, and then
    /// the `adoptCatalogueIds` re-run at the end resolves the just-renamed
    /// slug to the catalogue uuid it aliases. The end state is therefore the
    /// UUID, not the renamed slug — and nothing proved that until this test.
    @Test("with a catalogue present the rename resolves through to the uuid, log included")
    func resolvesToTheCatalogueWhenOneExists() throws {
        let db = try database()
        try seedSession(db)
        try db.writer.write { conn in
            try Exercise(id: "uuid-hack", name: "Hack Squat", slug: legacy("hack-squat")).insert(conn)
        }
        _ = try db.appendSet(sessionId: "s1", SetSnapshot(
            exerciseId: legacy("hack-squat"), setIndex: 1,
            weightKg: 100, reps: 5, setType: "normal"
        ))

        try migrate(db)

        // Not "onyx-hack-squat": the catalogue claims that slug, so v23's
        // rule takes it the rest of the way.
        #expect(try sets(in: db).map(\.exerciseId) == ["uuid-hack"])
        // And the log agrees, so an edit cannot undo it.
        try db.reprojectAll()
        #expect(try sets(in: db).map(\.exerciseId) == ["uuid-hack"])
    }

    /// The straggler path: an id that arrives AFTER the migration has run.
    /// `ExerciseIndex` re-stamps it rather than throwing, so a set logged by a
    /// watch on the previous build still resolves to the same catalogue row.
    @Test("an id still carrying the old stamp resolves instead of throwing")
    func resolvesAPostMigrationStraggler() throws {
        let catalogue = [RemoteExercise(id: "uuid-rdl", name: "Romanian Deadlift",
                                        slug: "onyx-romanian-deadlift")]
        let index = ExerciseIndex(catalogue)
        #expect(try index.id(forSlug: legacy("romanian-deadlift")) == "uuid-rdl")
        // And the migrated spelling still resolves to the very same row.
        #expect(try index.id(forSlug: "onyx-romanian-deadlift") == "uuid-rdl")
    }

    @Test("running it twice changes nothing")
    func isIdempotent() throws {
        let db = try database()
        try seedSession(db)
        _ = try db.appendSet(sessionId: "s1", SetSnapshot(
            exerciseId: legacy("bench-press"), setIndex: 1,
            weightKg: 80, reps: 5, setType: "normal"
        ))

        try migrate(db)
        let once = try sets(in: db)
        try migrate(db)

        #expect(try sets(in: db) == once)
        #expect(once.map(\.exerciseId) == ["onyx-bench-press"])
    }

    // MARK: - What the rewrite refuses to touch

    /// A uuid is a set that already reached the catalogue. Re-stamping one
    /// would point it at a row that does not exist.
    @Test("a catalogue uuid passes through untouched")
    func leavesUuidsAlone() throws {
        let uuid = UUID().uuidString
        #expect(ExerciseSlug.restamped(uuid) == nil)
        #expect(ExerciseSlug.restamped(uuid.lowercased()) == nil)
    }

    /// The version digit is what distinguishes the predecessor's stamp from an
    /// ordinary hyphenated id. Without this rule `ex-treadmill` — a real id
    /// shape in the fixtures — would be rewritten to `onyx-treadmill` and two
    /// movements would merge.
    @Test("an id whose first segment does not end in a digit is not a legacy stamp")
    func leavesOrdinaryHyphenatedIdsAlone() throws {
        #expect(ExerciseSlug.restamped("ex-treadmill") == nil)
        #expect(ExerciseSlug.restamped("treadmill") == nil)
        #expect(ExerciseSlug.restamped("onyx-treadmill") == nil)
        #expect(ExerciseSlug.restamped("port5-treadmill") == "onyx-treadmill")
        // An older stamp of the same family is caught by the same rule.
        #expect(ExerciseSlug.restamped("port4-treadmill") == "onyx-treadmill")
    }

    /// ── THE ONE THAT PINS TWO MACHINES TOGETHER ───────────────────────────
    /// `docs/sql/w1-onyx-wire.sql` decides "is this a predecessor stamp?" with
    /// `^[a-z]+[0-9]-`, and it runs against the same movement this function
    /// runs against. If the two disagree about one id, that movement is
    /// renamed on the phone and not on the server — one lift, two identities,
    /// which is the split the whole migration exists to prevent.
    ///
    /// The first draft of this function tested only "the character before the
    /// first hyphen is a digit". Every case in `refuses` below was renamed by
    /// Swift and left alone by Postgres under that rule. They are here because
    /// a reviewer constructed them, not because the live data holds one.
    @Test("the Swift predicate and the Postgres regex accept exactly the same ids")
    func matchesThePostgresPredicate() throws {
        // `^[a-z]+[0-9]-` — one or more LOWERCASE ASCII letters, then exactly
        // one ASCII digit, then the hyphen.
        let accepts = ["port5-bench-press", "port4-bench-press", "p9-x",
                       "abcdefgh1-long-stamp"]
        let refuses = [
            "5-bench-press",       // no letters before the digit
            "port55-bench-press",  // two digits — no lone digit abuts the hyphen
            "Port5-bench-press",   // uppercase
            "pört5-bench-press",   // non-ASCII letter
            "port-bench-press",    // no version digit at all
            "port5bench-press",    // the digit is not against the hyphen
            "ex-treadmill", "treadmill", "onyx-treadmill",
        ]

        for id in accepts {
            #expect(ExerciseSlug.restamped(id) != nil, "should accept \(id)")
        }
        for id in refuses {
            #expect(ExerciseSlug.restamped(id) == nil, "should refuse \(id)")
        }

        // And the same answers from the regex itself, so this test fails if
        // either side of the pair drifts rather than only if Swift does.
        let regex = try Regex("^[a-z]+[0-9]-")
        for id in accepts {
            #expect(try regex.firstMatch(in: id) != nil, "regex should accept \(id)")
        }
        for id in refuses where !id.hasPrefix("onyx-") {
            #expect(try regex.firstMatch(in: id) == nil, "regex should refuse \(id)")
        }
    }

    /// The body is never touched, so a name with digits, repeated hyphens or a
    /// collapsed parenthesis survives exactly as the catalogue spells it.
    @Test("only the stamp moves; the movement's own slug is preserved")
    func preservesTheBody() throws {
        #expect(ExerciseSlug.restamped(legacy("seated-cable-row-v-grip")) == "onyx-seated-cable-row-v-grip")
        #expect(ExerciseSlug.restamped(legacy("reverse-ez-bar-curl")) == "onyx-reverse-ez-bar-curl")
    }

    // MARK: - The catalogue's own two columns

    /// `exercises.slug` is the alias `ExerciseIndex` resolves a set through,
    /// and a shadow row an older build inserted carries the slug as its `id`.
    /// Both move, or the projection points at a row nothing can find.
    @Test("the catalogue's alias column and its shadow rows move with the sets")
    func migratesTheCatalogue() throws {
        let db = try database()
        try seedSession(db)
        try db.writer.write { conn in
            try Exercise(id: "uuid-hack", name: "Hack Squat", slug: legacy("hack-squat")).insert(conn)
            try Exercise(id: legacy("pec-deck"), name: "Pec Deck").insert(conn)
        }

        try migrate(db)

        let rows = try db.writer.read { conn in
            try Exercise.order(Column("name")).fetchAll(conn)
        }
        #expect(rows.map(\.name) == ["Hack Squat", "Pec Deck"])
        // The alias column moved, and the uuid it hangs off did not.
        #expect(rows[0].id == "uuid-hack")
        #expect(rows[0].slug == "onyx-hack-squat")
        // The shadow row's id IS a slug, so it moved as one.
        #expect(rows[1].id == "onyx-pec-deck")
    }

    // MARK: - The era

    /// `PhaseEra` has exactly two cases, so the migration finds its rows by
    /// EXCLUDING `ppl` rather than by naming the era it is replacing. A NULL
    /// era stays NULL: absent is not the same as this era, which is why
    /// `PhaseDef.era` is Optional in the first place.
    @Test("every era that is not ppl becomes onyx, and a null one stays null")
    func migratesTheEra() throws {
        let db = try database()
        try db.writer.write { conn in
            for (i, era) in [String?.some("port"), .some("ppl"), .none, .some("port")].enumerated() {
                try PlanPhaseRow(
                    userId: "u1", planId: "p\(i)", start: "2026-0\(i + 1)-05", kind: "cut",
                    name: "Block \(i)", short: nil, weeks: 4, numbered: true, firstWeek: nil,
                    era: era, eraTag: nil, updatedAt: Date()
                ).insert(conn)
            }
        }

        try migrate(db)

        let eras = try db.writer.read { conn in
            try Optional<String>.fetchAll(conn, sql: "SELECT era FROM plan_phases ORDER BY plan_id")
        }
        #expect(eras == ["onyx", "ppl", nil, "onyx"])
    }

    /// The enum's raw values ARE the wire format, and the migration above
    /// depends on there being exactly two of them. A third case added without
    /// a migration would be silently rewritten to `onyx` on every device.
    @Test("PhaseEra still has exactly the two cases the migration assumes")
    func eraHasTwoCases() throws {
        #expect(PhaseEra.onyx.rawValue == "onyx")
        #expect(PhaseEra.ppl.rawValue == "ppl")
        #expect(PhaseEra(rawValue: "onyx") == .onyx)
    }
}
