import Foundation
import Testing
import OnyxCore
@testable import Onyx

/// Precision A5 — the Cut-the-Stone rating and the finish sheet's wrist guard.
@MainActor
@Suite("Cut the Stone")
struct CutTheStoneTests {

    @Test("the five detents are the five stored words, CR-10 unchanged")
    func rpeMapping() {
        // Hand-written: the words the web stored and the battery reads.
        #expect(Effort.words.map(\.label) == ["Easy", "Solid", "Hard", "Brutal", "Everything"])
        #expect(Effort.words.map(\.cr10) == [5, 6.5, 8, 9, 10])
    }

    @Test("the vein runs from a 12 % sliver at Easy to the whole diagonal at Everything, and not at all unrated")
    func veinLength() {
        let levels = (0..<5).map { EffortSlab.level($0, of: 5) }
        for (level, expected) in zip(levels, [0.12, 0.34, 0.56, 0.78, 1.0] as [CGFloat]) {
            #expect(abs(level - expected) < 1e-9, "\(level) vs \(expected)")
        }
        #expect(EffortSlab.level(nil, of: 5) == 0)
    }

    @Test("heart rate and calories are asked only where a watch was, or on the athlete's word")
    func guardTable() {
        #expect(!WristMetrics.shown(evidence: false, liveBpmSeen: false, measured: false, carried: false))
        #expect(WristMetrics.shown(evidence: true, liveBpmSeen: false, measured: false, carried: false))
        #expect(WristMetrics.shown(evidence: false, liveBpmSeen: true, measured: false, carried: false))
        #expect(WristMetrics.shown(evidence: false, liveBpmSeen: false, measured: true, carried: false))
        #expect(WristMetrics.shown(evidence: false, liveBpmSeen: false, measured: false, carried: true))
    }

    @Test("unticked sets are the Sets tile's own remainder: planned minus done")
    func untickedCount() throws {
        let model = LoggerModel(
            day: PlanTemplates.day("onyx5", "arms"), phase: .bulk,
            warmupBout: WarmupCardio.Bout(name: "Treadmill", durationSec: 300)
        )
        let planned = model.plannedSets
        #expect(model.untickedSets == planned, "nothing ticked: every planned set")
        let first = try #require(model.exercises.first { !$0.rows.contains(where: \.isCardio) })
        let row = try #require(first.rows.first { $0.kind != .warmup })
        row.weightKg = 20
        row.reps = 10
        model.toggleDone(row, in: first)
        #expect(model.untickedSets == planned - 1)
    }
}
