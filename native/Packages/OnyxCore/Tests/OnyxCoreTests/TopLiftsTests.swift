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
        // Squat: highest rpe×kg and highest kg, but a low-rep set keeps its
        // Epley e1RM modest. Deadlift: low rpe×kg and low kg, but a high-rep
        // set gives it the higher e1RM — the axes really do disagree.
        let sets = [
            set("Squat", kg: 100, reps: 1, rpe: 10),
            set("Deadlift", kg: 90, reps: 30, rpe: 1),
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

    @Test("the Epley figure equals the app's existing estimated1RM formula for 100 kg x 5 reps")
    func epleyFigureMatchesApp() {
        // Epley's own definition (Training/Epley.swift): weight × (1 + reps/30),
        // then jsRound1 (Math.round(x*10)/10 — round-half-up to one decimal).
        // 100 × (1 + 5/30) = 116.6666… → 116.7. Computed as a literal here, NOT
        // by calling `Epley.oneRepMax` — this test must be able to fail if that
        // formula itself regresses.
        let expected = 116.7
        let groups = TopLifts.group([set("Bench Press", kg: 100, reps: 5, rpe: 9)], previous: [:])
        let oneRM = groups[0].lifts.first { $0.role == .oneRM }
        #expect(abs((oneRM?.figure ?? .nan) - expected) < 1e-6)
    }
}
