import Foundation
// ── WHY `@preconcurrency` ───────────────────────────────────────────────────
// `Activity` is imported as a plain non-Sendable class whose `update` and `end`
// are `nonisolated async`. Calling either from this main-actor-isolated type is
// therefore "sending a main-actor-isolated value to a nonisolated method",
// which Swift 6 rejects — and there is no arrangement of actors that fixes it,
// because the object cannot legally leave the main actor and the method cannot
// legally be called on it anywhere else.
//
// The alternative was `nonisolated(unsafe)` storage, which asserts the same
// thing while ALSO switching off checking on our own property. This scopes the
// downgrade to the SDK that has not been audited, which is what the attribute
// is for. Every call below is made from the main actor, and ActivityKit is
// documented as safe to call from it.
@preconcurrency import ActivityKit
import OnyxCore
import OnyxUI

/// Starts, feeds and ends the workout Live Activity.
///
/// ── WHY IT IS A PLAIN CLASS AND NOT PART OF THE MODEL ───────────────────────
/// `LoggerModel` is the state of the session and it has to keep working when
/// there is no Live Activity — activities are off by default for a fresh
/// install, unavailable on a Mac, and refused when the system is under pressure.
/// Every method here is best-effort by construction, and a screen whose state
/// machine sits behind an API that can decline is a screen that stops logging
/// when the Lock Screen is busy.
@MainActor
final class LiveActivityController {

    private var activity: Activity<OnyxWorkoutAttributes>?

    /// Cheap enough to ask every time and it can change while the app runs —
    /// the user can revoke Live Activities in Settings mid-session.
    private var isEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(model: LoggerModel, clock: any PauseControlling) {
        // ── THE SKIP BUTTON'S MAILBOX IS THIS TYPE'S JOB ────────────────────
        // `RestSkipIntent` is performed by the system with no reference to
        // anything, so something has to leave it one, and this controller is
        // the only object whose lifetime is exactly the card's — it already
        // brackets it with `start` and `end`.
        //
        // `[weak model]` because that closure lives in a global and outlives
        // the sheet on purpose: leaving the logger mid-session deliberately
        // keeps the card, and a strong capture would keep every session that
        // ever ran alive behind it. The `update` is not optional either — the
        // screen that normally pushes a `restEndsAt` change to the card is the
        // logger, which by definition is not on screen when the Lock Screen
        // button is the thing being tapped.
        RestSkip.handler = { [weak self, weak model, weak clock] in
            guard let model, let clock else { return }
            model.stopRest()
            self?.update(model: model, clock: clock)
        }
        // The ±15 s buttons, on the same terms and through the SAME model call
        // the exercise card's own nudge makes — so the Lock Screen and the deck
        // cannot end up counting two different rests.
        RestNudge.handler = { [weak self, weak model, weak clock] seconds in
            guard let model, let clock else { return }
            model.adjustRest(by: TimeInterval(seconds))
            self?.update(model: model, clock: clock)
        }
        guard isEnabled else { return }
        // Already holding a card — this controller is BORROWED from the Workout
        // tab, so re-entering the logger arrives here with one alive. Push the
        // current state instead of returning silently, or the Lock Screen keeps
        // whatever it was showing when the cover was dismissed: a paused clock
        // beside a phone that has since resumed.
        if activity != nil {
            update(model: model, clock: clock)
            return
        }
        // ── ADOPT WHAT THE LAST LAUNCH LEFT BEHIND ──────────────────────────
        // The handle lived only in memory, so a force-quit or a jetsam
        // mid-workout — which this app has a crash log for — left a Lock Screen
        // card nothing could feed or dismiss, and the next launch requested a
        // SECOND one beside it. ActivityKit keeps the running activities; the
        // one for this type is ours by definition.
        //
        // ── BUT ONLY IF IT IS THIS WORKOUT ──────────────────────────────────
        // `title` and `startedAt` are ATTRIBUTES, fixed for the activity's life
        // — `update` can only move the ContentState. Adopting yesterday's card
        // therefore keeps yesterday's name and start instant while today's sets
        // and tonnage flow into it: the Lock Screen reads CHEST & BACK B with a
        // 20-hour elapsed clock over Legs & Core A's numbers. `start()` ends the
        // old activity when a session is live, but after a jetsam `session` is
        // nil and nothing does. So a mismatch is ended rather than adopted.
        if let existing = Activity<OnyxWorkoutAttributes>.activities.first {
            if existing.attributes.startedAt == model.startedAt {
                activity = existing
                update(model: model, clock: clock)
                return
            }
            Task { await existing.end(nil, dismissalPolicy: .immediate) }
        }
        let attributes = OnyxWorkoutAttributes(
            title: model.day.label,
            startedAt: model.startedAt
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: Self.state(from: model, clock: clock), staleDate: nil)
            )
        } catch {
            // Declined, unsupported, or over the system's activity budget. The
            // workout is unaffected; there is nothing here worth surfacing to
            // someone standing at a machine.
            activity = nil
        }
    }

    func update(model: LoggerModel, clock: any PauseControlling) {
        guard let activity else {
            // The session may have started before the user enabled activities.
            start(model: model, clock: clock)
            return
        }
        Task {
            await activity.update(.init(state: Self.state(from: model, clock: clock), staleDate: nil))
        }
    }

    func end() {
        RestSkip.handler = nil
        RestNudge.handler = nil
        guard let activity else { return }
        self.activity = nil
        Task {
            // `.immediate`: the card is about a session that is over, and a
            // Lock Screen still counting a finished workout up is worse than no
            // card at all.
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// The token the card's muscle chip resolves, or nil when the movement has
    /// no mover this app can name.
    ///
    /// Read from `plan.movers`, which is where the deck's own rail reads it, so
    /// the Lock Screen and the card in your hand cannot disagree about what the
    /// set is for.
    private static func primaryMuscle(of exercise: LoggerModel.ExerciseState?) -> String? {
        guard let exercise else { return nil }
        if let token = exercise.plan.movers.primary.first,
           LandmarkMuscle.from(token: token) != nil {
            return token
        }
        return exercise.rows.contains(where: \.isCardio) ? "cardio" : nil
    }

    /// Compose the card. Every formatting decision the deck already made is
    /// carried across as text rather than re-derived on the far side.
    private static func state(
        from model: LoggerModel, clock: any PauseControlling
    ) -> OnyxWorkoutAttributes.ContentState {
        let current = model.currentSet

        var load = ""
        if let row = current?.row {
            if let kg = row.weightKg, let reps = row.reps {
                load = "\(OnyxFormat.kg(kg)) kg × \(reps)"
            } else if let kg = row.weightKg {
                // Weight-only while the reps are still being typed — which is
                // the state the card is in during every single set.
                load = "\(OnyxFormat.kg(kg)) kg"
            }
        }

        // ── WHY EVERY VALUE IS A TYPED LOCAL ────────────────────────────────
        // This was one literal. Two more fields took it past what the type
        // checker will solve in one expression — "unable to type-check this
        // expression in reasonable time", a build failure that names the whole
        // initialiser and none of the code in it. Each value annotated, so the
        // solver has nothing left to infer across.
        let rpeValue: Double? = current?.row.rpe
        let rpeText: String = rpeValue.map { "RPE \(OnyxFormat.rpe($0))" } ?? ""
        let setLabel: String = current.map { "Set \($0.ordinal) of \($0.total)" } ?? ""
        let volume: String = "\(OnyxFormat.volume(model.totalVolumeKg)) kg"
        let restTotal: Int? = model.restEndsAt == nil
            ? nil : Int(model.restDuration.rounded())
        let elapsed: String = clock.isPaused ? Clock.format(clock.elapsed()) : ""

        return .init(
            exercise: current?.exercise.name ?? "Session complete",
            setLabel: setLabel,
            load: load,
            rpe: rpeText,
            lastTime: current?.row.previous ?? "",
            volume: volume,
            setsDone: model.completedSets,
            setsPlanned: model.plannedSets,
            prsThisSession: model.recordCount,
            // The movement the card changes subject TO while resting, sent
            // only at a movement boundary. This was `current?.exercise.name`,
            // the same string as `exercise` above — the card said NEXT PRESS
            // while you rested between two sets of the press. The model's own
            // `nextExercise` is the following MOVEMENT and is the wrong string
            // for this wire: mid-exercise it would headline the lift after this
            // one over THIS one's load, `lastTime` and "Set 3 of 4", all of
            // which are `current?.row`. `restBoundaryExercise` is nil until the
            // cursor actually leaves the lift being rested from, so the name
            // and the numbers under it are always the same lift.
            nextExercise: model.restBoundaryExercise?.name,
            // ── AND WHY THE RATING IS READ OFF THE SEED ─────────────────────
            // `row.rpe` on an unticked row is what E4's seed REMEMBERED from
            // the last time this set number was performed, which is exactly
            // "what did this cost me last time". Once the set is ticked it
            // becomes this session's own rating and stops being a `prev`, so
            // the card only ever draws it while resting.
            lastRpe: rpeValue.map { "RPE \(OnyxFormat.rpe($0))" },
            restEndsAt: model.restEndsAt,
            // The clock, mirrored. `timerOrigin` is already moved forward by
            // whatever has been banked in pauses, so the card counts the same
            // seconds the hero does without an update per second — and the
            // paused reading is composed HERE, because the producer owns every
            // formatting rule on this card.
            timerOrigin: clock.timerOrigin,
            isPaused: clock.isPaused,
            elapsed: elapsed,
            // The movement's own muscle, as a token the card resolves through
            // `Color.onyx.muscle` — see `ContentState.primaryMuscle`. A bout
            // has no mover in `MuscleMap` (a treadmill is not a lift), and the
            // literal is what the card draws its Tide chip from.
            primaryMuscle: primaryMuscle(of: current?.exercise),
            // The same rating as `rpe` above, in the register the card needs to
            // TINT with rather than to draw — see `ContentState.rpeValue`.
            rpeValue: rpeValue,
            // Nil when not resting, so the card's bar and the card's clock
            // appear and leave together.
            restTotalSec: restTotal,
            dayKey: model.day.key
        )
    }
}
