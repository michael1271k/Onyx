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

    /// Upper B, cut phase. `logged: true` reproduces a real mid-session state;
    /// `resting: true` leaves the rest clock running, which is the only state
    /// the nav-bar capsule exists in and therefore the only one that can be
    /// photographed.
    static func previewUpperB(logged: Bool = false, resting: Bool = false) -> LoggerModel {
        let model = LoggerModel(
            day: PlanTemplates.day("onyx5", "cb_b"),
            phase: .cut,
            startedAt: Date().addingTimeInterval(-22 * 60)
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
    /// screenshot. The catalogue has to carry the treadmill too, or the deck
    /// opens without its bout (`catalogueHasWarmupCardio`) and the cardio dot —
    /// the one dot on the timeline that could never fill before W3 — cannot be
    /// photographed either.
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
            try Exercise(id: "pv-cardio", name: WarmupCardio.name).insert(db)
            for (i, set) in previous.enumerated() {
                try Exercise(id: "pv-\(i)", name: set.name).insert(db)
            }
            let start = LogicalDay.date(fromISO: date)!.addingTimeInterval(17 * 3600)
            try WorkoutSession(
                id: "pv-session", userId: userId, dayKey: "cb_b", date: date, startedAt: start,
                endedAt: start.addingTimeInterval(58 * 60), durationMin: 58
            ).insert(db)
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
            startedAt: Date().addingTimeInterval(-22 * 60)
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
