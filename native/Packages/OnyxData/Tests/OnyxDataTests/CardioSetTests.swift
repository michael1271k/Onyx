import Foundation
import GRDB
import Testing
@testable import OnyxData

/// The trip a cardio set makes, end to end.
///
/// ── WHAT WAS BROKEN ─────────────────────────────────────────────────────────
/// `hotfix-polish.sql (git history)` gave `workout_sets` three columns on 2026-09-07
/// — `duration_sec`, `incline`, `distance_km` — and wrote the first row that
/// uses them: the treadmill that opens that session, five minutes at incline 2
/// for 0.37 km, `weight_kg 0, reps 0`. None of the three could reach the phone.
/// The local table had no columns for them, `RemoteSetRow` did not select them,
/// and the report renders `weight_kg` × `reps`, so the phone drew five minutes
/// of walking as `0kg × 0`.
///
/// This walks the whole path in one test, because every hop in it is a place
/// the axes have already been dropped once:
///
/// ── AND THEN A FOURTH AXIS ──────────────────────────────────────────────────
/// `cardio-elevation.sql (git history)` adds `elevation_m` — total ascent in metres,
/// MEASURED rather than `incline` × `distance_km`, because a real bout changes
/// incline and `incline` keeps one reading. It makes exactly the journey below,
/// and it is asserted at every hop for the reason the other three are: each hop
/// is a place an axis has already been dropped once.
///
///   1. **the migration** — `v18` adds three columns and `v19` a fourth, both
///      guarded;
///   2. **the pull** — `applyPulledSets` carries them off the wire;
///   3. **the local row** — the projection holds them;
///   4. **the report read** — `historySets` selects them, which is what the
///      Session Report's `DetailSet` is built from;
///   5. **the wire row back** — `setRow` sends them, so the next push does not
///      blank the only row in the database that uses the columns;
///   6. **an EDIT** — the fold. `seedEventLog` turns a pulled session's rows
///      into `.append` events and `reproject` rebuilds the rows from them, so
///      an axis `SetSnapshot` cannot carry is an axis the first edit erases.
///      That erasure is silent and then pushes itself over the server's copy.
@Suite("A cardio set survives the trip to the phone")
struct CardioSetTests {

    private let user = "u1"
    private let session = "b6a936a8-c730-413e-8c27-14575b093983"

    /// The live row, field for field.
    private var treadmill: RemoteSetRow {
        RemoteSetRow(
            id: "srv-treadmill", sessionId: session, exerciseId: "helix5-treadmill", userId: user,
            setNumber: 1, weightKg: 0, reps: 0, setType: "warmup",
            side: nil, pairId: nil, est1rmKg: nil, rpe: nil, exerciseOrder: 0,
            // 12 m of ascent over 0.37 km. `incline` × `distance_km` says 7.4,
            // and the disagreement is the whole point of storing it: the bout
            // was walked at 2 %, then steeper, then flat, and `incline` kept
            // the first reading. A test that used 7.4 would pass just as well
            // against a derived column.
            durationSec: 300, incline: 2.0, distanceKm: 0.370, elevationM: 12
        )
    }

    /// A lifted set from the same session, to prove the axes stay nil on the
    /// row that has no business carrying them.
    private var press: RemoteSetRow {
        RemoteSetRow(
            id: "srv-press", sessionId: session, exerciseId: "helix5-incline-press", userId: user,
            setNumber: 1, weightKg: 42, reps: 10, setType: "normal",
            side: nil, pairId: nil, est1rmKg: 56, rpe: 8, exerciseOrder: 1,
            durationSec: nil, incline: nil, distanceKm: nil, elevationM: nil
        )
    }

    @Test("migration → pull → local row → report read → wire row, and an edit does not erase it")
    func survivesTheRoundTrip() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")

        // 1 · THE MIGRATION. `v18` ran as part of opening the store.
        let columns = try db.writer.read { try Set($0.columns(in: "workout_sets").map(\.name)) }
        #expect(columns.isSuperset(of: ["duration_sec", "incline", "distance_km", "elevation_m"]))

        // The session the puller would have written first. Adopted rather than
        // logged: it holds no `set_events`, which is what lets `applyPulledSets`
        // take it at all.
        try db.writer.write { conn in
            try WorkoutSession(
                id: session, userId: user, dayKey: "cb_a", date: "2026-09-07",
                startedAt: Date(), endedAt: Date()
            ).insert(conn)
            try Exercise(id: "helix5-treadmill", name: "Treadmill").insert(conn)
            try Exercise(id: "helix5-incline-press", name: "Incline DB Press").insert(conn)
        }

        // 2 · THE PULL.
        #expect(try db.applyPulledSets([treadmill, press]) == 2)

        // 3 · THE LOCAL ROW.
        let local = try db.sets(sessionId: session)
        let walked = try #require(local.first { $0.id == "srv-treadmill" })
        #expect(walked.durationSec == 300)
        #expect(walked.incline == 2.0)
        #expect(walked.distanceKm == 0.370)
        #expect(walked.elevationM == 12)
        // `weight_kg 0, reps 0` is the whole reason the three columns exist —
        // the set really does carry no load and no reps, so a reader that has
        // only those two has nothing true to say about it.
        #expect(walked.weightKg == 0 && walked.reps == 0)
        let lifted = try #require(local.first { $0.id == "srv-press" })
        #expect(lifted.durationSec == nil && lifted.incline == nil && lifted.distanceKm == nil)
        #expect(lifted.elevationM == nil)

        // 4 · THE REPORT READ. `historySets` is what `SessionAnalysis` folds
        // into `DetailSet`, and it names its columns one by one — a column
        // missing from that SELECT is a column the report cannot render.
        let history = try db.historySets(sessionId: session)
        let row = try #require(history.first { $0.id == "srv-treadmill" })
        #expect(row.durationSec == 300 && row.incline == 2.0 && row.distanceKm == 0.370)
        #expect(row.elevationM == 12)

        // 5 · THE WIRE ROW BACK.
        let wire = try SyncTranslation.setRow(walked, userId: user, exerciseId: "uuid-treadmill")
        #expect(wire.durationSec == 300 && wire.incline == 2.0 && wire.distanceKm == 0.370)
        #expect(wire.elevationM == 12)
        let encoded = try JSONSerialization.jsonObject(
            with: OnyxJSON.encoder.encode(wire)
        ) as? [String: Any]
        #expect(encoded?["duration_sec"] as? Int == 300)
        #expect(encoded?["incline"] as? Double == 2.0)
        #expect(encoded?["distance_km"] as? Double == 0.370)
        #expect(encoded?["elevation_m"] as? Double == 12)

        // 6 · AN EDIT ELSEWHERE IN THE SESSION.
        //
        // Correcting the PRESS seeds the event log for the WHOLE session — the
        // treadmill included — and reprojects every row from it. Before
        // `SetSnapshot` carried the axes this is where they died: the fold
        // rebuilt the treadmill as `0kg × 0`, and the next drain pushed those
        // nulls back over the repair.
        _ = try db.amendSet(sessionId: session, setId: "srv-press", reps: 11)
        let after = try #require(try db.sets(sessionId: session).first { $0.id == "srv-treadmill" })
        #expect(after.durationSec == 300)
        #expect(after.incline == 2.0)
        #expect(after.distanceKm == 0.370)
        // The fourth axis through the SNAPSHOT and the FOLD. `seedEventLog`
        // built a `SetSnapshot` for this row and `reproject` rebuilt the row
        // from it, so this passing means the ascent survived a round trip
        // through JSON on the event body — the hop that has no column to
        // forget, only a key.
        #expect(after.elevationM == 12)

        // And out again, from the REPROJECTED row rather than the pulled one.
        let resent = try SyncTranslation.setRow(after, userId: user, exerciseId: "uuid-treadmill")
        #expect(resent.elevationM == 12, "an edited session pushes the ascent back, not a null")
    }
}
