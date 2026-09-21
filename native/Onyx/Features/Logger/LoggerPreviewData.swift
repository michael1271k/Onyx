import Foundation
import OnyxCore
import OnyxData

/// Real numbers, so the design is reviewed against real density.
///
/// ── WHY THIS IS THE ACTUAL SESSION AND NOT LOREM IPSUM ──────────────────────
/// A logger previewed on `3 × 10 @ 50 kg` looks fine and tells you nothing. The
/// loads below are from a real Upper B on a cut — 49.5 kg, 42.5 kg, 13.75 kg —
/// and they are what expose the layout problems that matter: a four-character
/// load beside a two-character rep count, an RPE of 9.5 rather than 9, and
/// "Single Arm Triceps Pushdown" as a title on a 390 pt screen.
///
/// It also runs the SAME model as the device. A preview built from a parallel
/// mock is a preview that can be right about code the device does not run.
#if DEBUG
extension LoggerModel {

    /// The bout the preview decks open with.
    ///
    /// HARNESS DATA, like every other number on this page. Five minutes at 2 %
    /// over 0.37 km is what the founder's treadmill warm-up was, and it lived
    /// in `WarmupCardio` as three constants prescribed to every account until
    /// this wave. The opener is the athlete's own last `cardio_logs` row now,
    /// so a fixture that wants the card has to bring a bout — and the shots
    /// that review the cardio card (`set-row-cardio`, `logger`) need one.
    nonisolated static let previewBout = WarmupCardio.Bout(
        name: "Treadmill", durationSec: 300, distanceKm: 0.37, inclinePct: 2
    )

    /// Upper B, cut phase. `logged: true` reproduces a real mid-session state;
    /// `resting: true` leaves the rest clock running, which is the only state
    /// the nav-bar capsule exists in and therefore the only one that can be
    /// photographed.
    static func previewUpperB(logged: Bool = false, resting: Bool = false) -> LoggerModel {
        let model = LoggerModel(
            day: PlanTemplates.day("onyx5", "cb_b"),
            phase: .cut,
            startedAt: Date().addingTimeInterval(-22 * 60),
            warmupBout: previewBout
        )
        guard logged else { return model }

        // Chest Press — three at 40, the last one graded 9.5.
        model.fill("Chest Press", [(40, 12, 9), (40, 10, 9), (40, 10, 9.5)])
        // Neutral-Grip Lat Pulldown — a load increase inside the rep window,
        // which is exactly what double progression looks like on a good day.
        model.fill("Neutral-Grip Lat Pulldown", [(47, 12, 8.5), (49.5, 11, 9.5)])
        // The second row is taken to FAILURE — 10, `RpeLadder`'s top rung.
        //
        // Seeded on purpose and seeded HERE rather than on the chest press:
        // the deck's badge draws an `F` for a set rated 10, and until this wave
        // nothing in six weeks of preview data sat on that rung, so the state
        // could not be photographed at all. It goes on a row that is NOT a
        // record because a record outranks a failure in the badge — putting
        // both on one row photographs the trophy and proves nothing about the
        // F. The trophy itself needs no seeding: the pulldown above takes a
        // live record through `toggleDone`, which is the real engine.
        model.fill("Seated Cable Row (Wide Grip)", [(42.5, 12, 9), (42.5, 10, 10)])
        model.fill("Single Arm Cable Crossover", [(7.5, 15, 8)])
        if resting, let next = model.currentSet?.exercise { model.startRest(for: next) }
        return model
    }

    /// The same Upper B, with ONE previous session of this day behind it and a
    /// finished treadmill bout on the front.
    ///
    /// ── WHY A STORE, ON A SCREEN THAT DRAWS NO ROWS ─────────────────────────
    /// Without one `SessionSeed` falls to the PROGRAM tier — `wk1Kg` at the rep
    /// floor, a load chosen in July — so `Top lifts` has nothing to compare
    /// against and the arrows it exists to draw are unreachable in a
    /// screenshot. The opener is handed in (`previewBout`) rather than read
    /// off this store: the deck would otherwise open without its bout and the
    /// cardio dot — the one dot on the timeline that could never fill before
    /// W3 — could not be photographed either.
    ///
    /// The previous loads are deliberately BELOW today's on the pulldown (47 →
    /// 49.5) and above them on the row (45 → 42.5), so one lift rises and
    /// another falls in the same photograph.
    static func previewUpperBWithHistory() -> (model: LoggerModel, store: AppDatabase) {
        let store = try! AppDatabase.inMemory(deviceId: "preview-logger")
        let userId = PreviewCatalogue.userId
        let previous: [(name: String, kg: Double, reps: Int, rpe: Double)] = [
            ("Chest Press", 40, 11, 9),
            ("Neutral-Grip Lat Pulldown", 47, 11, 9),
            ("Seated Cable Row (Wide Grip)", 45, 10, 9),
            ("Single Arm Cable Crossover", 7.5, 14, 8),
        ]
        let date = LogicalDay.iso(Date().addingTimeInterval(-7 * 24 * 3600))
        try? store.seedRows { db in
            try Exercise(id: "pv-cardio", name: previewBout.name).insert(db)
            for (i, set) in previous.enumerated() {
                try Exercise(id: "pv-\(i)", name: set.name).insert(db)
            }
            let start = LogicalDay.date(fromISO: date)!.addingTimeInterval(17 * 3600)
            try WorkoutSession(
                id: "pv-session", userId: userId, dayKey: "cb_b", date: date, startedAt: start,
                endedAt: start.addingTimeInterval(58 * 60), durationMin: 58,
                // In the same range the deck itself logs (~3,400 kg over eight
                // sets). A fixture whose history is three times its own session
                // photographs a −68 % trail and reviews an arithmetic bug that
                // does not exist.
                totalVolumeKg: 3_640
            ).insert(db)
            // ── FOUR MORE, OLDER, AND NOTHING BUT A TONNAGE (W10) ───────────
            // The finish sheet's trail is `splitTonnage`, which reads
            // `workout_sessions.total_volume_kg` and no sets at all — so these
            // carry the column and nothing else. Without them the spark has
            // one point behind today's and `Sparkline` refuses to draw under
            // two, which would photograph the sheet as it looked before the
            // trail existed.
            //
            // OLDER than `pv-session`, deliberately. `SessionSeedBuilder
            // .sessionsForSeed` takes the most recent qualifying session as
            // the seed, and a set-less session in front of `pv-session` would
            // become "last time" — the deck would open on the program's July
            // loads and `Top lifts` would lose every arrow it exists to draw.
            //
            // The shape is a real one: two steady weeks, a lighter one, then a
            // build. A monotone ramp would draw a straight line and prove
            // nothing about a trail whose whole job is to show a wobble.
            for (back, tonnage) in [(5, 3_180.0), (4, 3_420.0), (3, 2_960.0), (2, 3_510.0)] {
                let day = LogicalDay.iso(Date().addingTimeInterval(Double(-back * 7 * 24 * 3600)))
                let began = LogicalDay.date(fromISO: day)!.addingTimeInterval(17 * 3600)
                try WorkoutSession(
                    id: "pv-session-w\(back)", userId: userId, dayKey: "cb_b", date: day,
                    startedAt: began, endedAt: began.addingTimeInterval(56 * 60),
                    durationMin: 56, totalVolumeKg: tonnage
                ).insert(db)
            }
            for (i, set) in previous.enumerated() {
                try WorkoutSet(
                    id: "pv-session-\(i)", sessionId: "pv-session", exerciseId: "pv-\(i)",
                    setIndex: i + 1, weightKg: set.kg, reps: set.reps,
                    est1rmKg: OneRepMax.estimate(weight: set.kg, reps: Double(set.reps)),
                    rpe: set.rpe, foldOrder: i
                ).insert(db)
            }
        }

        let model = LoggerModel(
            day: PlanTemplates.day("onyx5", "cb_b"),
            phase: .cut,
            store: store,
            userId: userId,
            startedAt: Date().addingTimeInterval(-22 * 60),
            warmupBout: previewBout
        )
        model.fill("Chest Press", [(40, 12, 9), (40, 10, 9), (40, 10, 9.5)])
        model.fill("Neutral-Grip Lat Pulldown", [(47, 12, 8.5), (49.5, 11, 9.5)])
        model.fill("Seated Cable Row (Wide Grip)", [(42.5, 12, 9), (42.5, 10, 10)])
        model.fill("Single Arm Cable Crossover", [(7.5, 15, 8)])
        // The bout, done — `dotProgress`'s cardio branch, and the only thing
        // that makes the treadmill's dot anything but empty.
        if let bout = model.exercises.first(where: { $0.rows.allSatisfy { $0.isCardio } }),
           let row = bout.rows.first, !row.isDone {
            model.toggleDone(row, in: bout)
        }
        model.stopRest()
        // The SAME store, handed back: `LiveStatsView` reads the previous
        // session's sets through `environment.database`, and a fixture that
        // seeded only the model's own store would photograph a card with no
        // arrows on it while the deck behind it had a history.
        //
        // The STORE and not an `AppEnvironment`: the harness wraps it in one,
        // and a test that wants to check the seed should not have to start an
        // app environment — a second one in a unit-test process brings a
        // Supabase client and its listeners with it.
        return (model, store)
    }

    /// The finish-sheet fixture, re-timed for the heart-rate chart (W5).
    ///
    /// `previewUpperBWithHistory` logs its nine sets in one instant, which is
    /// nine commits at the same second and a chart with one segment and eight
    /// empty ones. This spreads them over the last forty minutes — the session
    /// starts 46 minutes ago, the first commit at +4, the last at +38 — so the
    /// segments the `TelemetrySeed`'s series is cut into have widths. Timestamps
    /// are the only thing rewritten; the fold order, the loads and the store
    /// are the fixture's own. `closed` also ends the session three minutes
    /// ago, which is what `SessionDetailView` needs to open on it.
    static func previewTelemetry(closed: Bool) -> (model: LoggerModel, store: AppDatabase) {
        let fixture = previewUpperBWithHistory()
        guard let sessionId = fixture.model.sessionId else { return fixture }
        let start = Date().addingTimeInterval(-46 * 60)
        let appends = ((try? fixture.store.setEvents(sessionId: sessionId)) ?? []).filter { $0.kind == .append }
        try? fixture.store.seedRows { db in
            try db.execute(sql: "UPDATE workout_sessions SET started_at = ? WHERE id = ?", arguments: [start, sessionId])
            let span = 34.0 * 60
            for (i, event) in appends.enumerated() {
                let at = start.addingTimeInterval(4 * 60 + span * Double(i) / Double(max(1, appends.count - 1)))
                try db.execute(sql: "UPDATE set_events SET created_at = ? WHERE id = ?", arguments: [at, event.id])
            }
            if closed {
                try db.execute(
                    sql: "UPDATE workout_sessions SET ended_at = ?, duration_min = 41 WHERE id = ?",
                    arguments: [start.addingTimeInterval(43 * 60), sessionId]
                )
            }
        }
        return fixture
    }

    /// Tick a run of sets on one movement, exactly as the UI would.
    ///
    /// It calls `toggleDone` rather than setting `isDone`, so a preview
    /// exercises the record rule, the rest timer and the store write-through —
    /// the parts most likely to be wrong.
    private func fill(_ exerciseName: String, _ sets: [(Double, Int, Double?)]) {
        guard let exercise = exercises.first(where: { $0.name == exerciseName }) else { return }
        for (index, entry) in sets.enumerated() {
            while exercise.rows.count <= index { addSet(to: exercise) }
            let row = exercise.rows[index]
            row.weightKg = entry.0
            row.reps = entry.1
            row.rpe = entry.2
            toggleDone(row, in: exercise)
        }
        // The rest clock is a state the design has to be reviewed IN, but a
        // preview that seeded it from the last tick would show a bar counting
        // down from whichever movement happened to be filled last.
        stopRest()
    }
}
#endif
