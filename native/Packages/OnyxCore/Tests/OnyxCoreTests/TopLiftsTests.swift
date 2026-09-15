import Foundation
import Testing
@testable import OnyxCore

@Suite("TopLifts — grouping the session's best lifts per exercise")
struct TopLiftsTests {

    private func set(
        _ exercise: String, kg: Double, reps: Int, rpe: Double? = nil,
        recordAxes: Swift.Set<PrAxis> = []
    ) -> TopLifts.Set {
        TopLifts.Set(exercise: exercise, kg: kg, reps: reps, rpe: rpe, recordAxes: recordAxes)
    }

    @Test("one exercise winning all three roles is exactly one group with three lifts in role order")
    func oneExerciseSweepsAllRoles() {
        let sets = [set("Bench Press", kg: 100, reps: 5, rpe: 9)]
        let groups = TopLifts.group(sets, previous: [:])
        #expect(groups.count == 1)
        #expect(groups[0].exercise == "Bench Press")
        #expect(groups[0].lifts.map(\.role) == [.hardest, .heaviest, .oneRM])
    }

    @Test("two exercises: A wins hardest+heaviest, B wins 1RM — A first, B second with one lift")
    func twoExercisesOrderedByFirstRoleWon() {
        // Squat: highest rpe×kg and highest kg, but a single keeps its e1RM at
        // the load itself (Brzycki is `36/36` at one rep). Deadlift: low rpe×kg
        // and low kg, but twelve reps put its estimate at 90 × 36/25 = 129.6 —
        // the axes really do disagree.
        //
        // Twelve and not thirty: thirty reps is past `OneRepMax.maxReps`, so
        // the Deadlift would carry no estimate at all and this test would be
        // asserting the ceiling rather than the disagreement it is for.
        let sets = [
            set("Squat", kg: 100, reps: 1, rpe: 10),
            set("Deadlift", kg: 90, reps: 12, rpe: 1),
        ]
        let groups = TopLifts.group(sets, previous: [:])
        #expect(groups.count == 2)
        #expect(groups[0].exercise == "Squat")
        #expect(groups[0].lifts.map(\.role) == [.hardest, .heaviest])
        #expect(groups[1].exercise == "Deadlift")
        #expect(groups[1].lifts.map(\.role) == [.oneRM])
    }

    @Test("delta signs: up beyond +0.05, down beyond -0.05, flat within, nil with no previous")
    func deltaSigns() {
        let up = TopLifts.group(
            [set("Row", kg: 102.5, reps: 5, rpe: 8)],
            previous: ["Row": TopLifts.Best(kg: 100, rpeKg: nil, e1rm: nil)]
        )
        #expect(up[0].lifts.first { $0.role == .heaviest }?.delta == .up)

        let down = TopLifts.group(
            [set("Row", kg: 97.5, reps: 5, rpe: 8)],
            previous: ["Row": TopLifts.Best(kg: 100, rpeKg: nil, e1rm: nil)]
        )
        #expect(down[0].lifts.first { $0.role == .heaviest }?.delta == .down)

        let flat = TopLifts.group(
            [set("Row", kg: 100.04, reps: 5, rpe: 8)],
            previous: ["Row": TopLifts.Best(kg: 100, rpeKg: nil, e1rm: nil)]
        )
        #expect(flat[0].lifts.first { $0.role == .heaviest }?.delta == .flat)

        let noPrevious = TopLifts.group([set("Row", kg: 100, reps: 5, rpe: 8)], previous: [:])
        #expect(noPrevious[0].lifts.first { $0.role == .heaviest }?.delta == nil)
    }

    @Test("isRecord: heaviest winner with .weight is a record; the same set as 1RM winner with only .weight is not; hardest is never a record")
    func isRecordFromAxes() {
        let sets = [set("Press", kg: 60, reps: 5, rpe: 9, recordAxes: [.weight])]
        let groups = TopLifts.group(sets, previous: [:])
        let lifts = groups[0].lifts
        #expect(lifts.first { $0.role == .heaviest }?.isRecord == true)
        #expect(lifts.first { $0.role == .oneRM }?.isRecord == false)
        #expect(lifts.first { $0.role == .hardest }?.isRecord == false)
    }

    @Test("an unrated set with the largest kg wins Heaviest but cannot win Hardest")
    func unratedSetCannotWinHardest() {
        let sets = [
            set("Curl", kg: 200, reps: 3, rpe: nil),
            set("Curl", kg: 20, reps: 10, rpe: 8),
        ]
        let groups = TopLifts.group(sets, previous: [:])
        #expect(groups.count == 1)
        let lifts = groups[0].lifts
        #expect(lifts.first { $0.role == .heaviest }?.set.kg == 200)
        #expect(lifts.first { $0.role == .hardest }?.set.kg == 20)
    }

    @Test("a set with reps 0 (cardio) is ignored for every role")
    func zeroRepsIgnoredEverywhere() {
        let sets = [
            set("Treadmill", kg: 999, reps: 0, rpe: 10),
            set("Curl", kg: 20, reps: 10, rpe: 8),
        ]
        let groups = TopLifts.group(sets, previous: [:])
        #expect(groups.count == 1)
        #expect(groups[0].exercise == "Curl")
    }

    @Test("tie on kg: the later set in input order wins Heaviest")
    func tieGoesToLaterSet() {
        let earlier = set("Row", kg: 100, reps: 5, rpe: 7)
        let later = set("Row", kg: 100, reps: 6, rpe: 7)
        let groups = TopLifts.group([earlier, later], previous: [:])
        let heaviest = groups[0].lifts.first { $0.role == .heaviest }
        #expect(heaviest?.set.reps == 6)
    }

    @Test("the e1RM figure equals the app's own estimate for 100 kg x 5 reps")
    func oneRepMaxFigureMatchesApp() {
        // Brzycki's own definition (Training/OneRepMax.swift): weight × 36 /
        // (37 − reps), then jsRound2 (Math.round(x*100)/100 — round-half-up to
        // two decimals). 100 × 36/32 = 112.5 exactly. Computed as a literal
        // here, NOT by calling `OneRepMax.estimate` — this test must be able to
        // fail if that formula itself regresses.
        let expected = 112.5
        let groups = TopLifts.group([set("Bench Press", kg: 100, reps: 5, rpe: 9)], previous: [:])
        let oneRM = groups[0].lifts.first { $0.role == .oneRM }
        #expect(abs((oneRM?.figure ?? .nan) - expected) < 1e-6)
    }

    // MARK: - The bar the arrows are drawn against

    private func seedSet(
        _ session: String, _ exercise: String, kg: Double, reps: Int,
        rpe: Double? = nil, setType: String? = nil
    ) -> SeedSet {
        SeedSet(
            sessionId: session, exerciseName: exercise, order: 1,
            weightKg: kg, reps: reps, rpe: rpe, setType: setType
        )
    }

    private func seedSession(_ id: String, _ date: String) -> SeedSession {
        SeedSession(id: id, dayKey: "cb_b", date: date, startedAt: "\(date)T17:00:00Z", maintenance: false)
    }

    /// The reason `previousBests` exists at all rather than reading the deck's
    /// own `SessionSeed`: a seeded row is the PROPOSAL, bumped to the ladder's
    /// suggested load at the rep floor with its remembered rating dropped. This
    /// asserts the bar is the SET THAT WAS LIFTED — 100 × 12 at RPE 9 — and not
    /// anything derived from what the ladder wants next.
    @Test("the bar is last session's own numbers, all three roles")
    func previousBestsReadTheSessionThatHappened() {
        let bests = TopLifts.previousBests(
            sessions: [seedSession("s1", "2026-09-08")],
            sets: [
                seedSet("s1", "Chest Press", kg: 90, reps: 12, rpe: 8),
                seedSet("s1", "Chest Press", kg: 100, reps: 12, rpe: 9),
            ]
        )
        let best = bests["Chest Press"]
        #expect(best?.kg == 100)
        #expect(best?.rpeKg == 900)
        // 100 × 36/25 = 144.
        #expect(abs((best?.e1rm ?? .nan) - 144) < 1e-6)

        // And it is the bar `group` actually draws against: 102.5 today is UP.
        let groups = TopLifts.group([set("Chest Press", kg: 102.5, reps: 12, rpe: 9)], previous: bests)
        #expect(groups[0].lifts.first { $0.role == .heaviest }?.delta == .up)
    }

    @Test("the newest session that LIFTED a movement wins it, warm-ups aside")
    func previousBestsWalkBackPastASessionThatOnlyWarmedUp() {
        let bests = TopLifts.previousBests(
            // Newest first, as `sessionsForSeed` returns them.
            sessions: [seedSession("s2", "2026-09-15"), seedSession("s1", "2026-09-08")],
            sets: [
                // Last Tuesday you set up, warmed up and stopped.
                seedSet("s2", "Chest Press", kg: 40, reps: 10, setType: "warmup"),
                seedSet("s1", "Chest Press", kg: 100, reps: 12, rpe: 9),
                // A movement only the older session holds is still answered.
                seedSet("s1", "Preacher Curl", kg: 20, reps: 12, rpe: 8),
            ]
        )
        #expect(bests["Chest Press"]?.kg == 100)
        #expect(bests["Preacher Curl"]?.kg == 20)
        // A movement nobody has lifted has no bar, which draws no arrow.
        #expect(bests["Face Pull"] == nil)
    }

    @Test("an unrated previous session leaves Hardest without a bar, not with a zero")
    func previousBestsRpeKgIsNilWhenNothingWasRated() {
        let bests = TopLifts.previousBests(
            sessions: [seedSession("s1", "2026-09-08")],
            sets: [seedSet("s1", "Chest Press", kg: 100, reps: 12)]
        )
        #expect(bests["Chest Press"]?.rpeKg == nil)
        #expect(bests["Chest Press"]?.kg == 100)
        let groups = TopLifts.group([set("Chest Press", kg: 100, reps: 12, rpe: 9)], previous: bests)
        #expect(groups[0].lifts.first { $0.role == .hardest }?.delta == nil)
        #expect(groups[0].lifts.first { $0.role == .heaviest }?.delta == .flat)
    }

    @Test("the bar is keyed canonically, so an alias spelling still finds it")
    func previousBestsKeyIsCanonical() {
        let bests = TopLifts.previousBests(
            sessions: [seedSession("s1", "2026-09-08")],
            sets: [seedSet("s1", "Lat Pulldown (Cable)", kg: 65, reps: 11, rpe: 8)]
        )
        #expect(bests[ExerciseAliases.canonicalName("Lat Pulldown (Cable)")]?.kg == 65)
    }

}
