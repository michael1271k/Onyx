import Foundation
import Testing
@testable import OnyxCore

/// The PR guard (founder decision Q12, design 11 — Precision Lane C): a trophy
/// needs at least one prior session-backed set OR a floor for this user +
/// exercise. A first-ever exercise shows a quiet "Baseline" mark and never a
/// trophy — not even on its second set of the same session.
@Suite("PR guard — provenance")
struct PrProvenanceTests {

    private func set(_ key: String, _ kg: Double, _ reps: Double, setType: String? = nil) -> PrCandidateSet {
        PrCandidateSet(key: key, weightKg: kg, reps: reps, setType: setType)
    }

    @Test("provenance per key: session-backed, floor-only, none")
    func provenanceTable() {
        let b = PrEngine.buildBaselines(
            [
                BaselineSetRow(key: "A", weightKg: 100, reps: 5),
                BaselineSetRow(key: "W", weightKg: 60, reps: 10, setType: "warmup"),  // a warm-up sets no bar
            ],
            isTimed: { _ in false },
            floorFor: { $0 == "B" ? PrFloor(weight: 80) : nil },
            candidateKeys: ["A", "B", "C", "W"]
        )
        #expect(b.provenance["A"] == .sessionBacked)
        #expect(b.provenance["B"] == .floorOnly)
        #expect(b.provenance["C"] == PrProvenance.none)
        #expect(b.provenance["W"] == PrProvenance.none, "a history of warm-ups is no history")
        // A floor-only key now HAS a bar — the floor is folded in for the
        // candidate keys too, not only for keys already in the rows.
        #expect(b.bestWeight.contains { $0.key == "B" && $0.value == 80 })
    }

    @Test("a first-ever exercise is a baseline, on every set, and counts no PR")
    func firstEverIsBaseline() {
        let b = PrEngine.buildBaselines([], isTimed: { _ in false }, candidateKeys: ["New Lift"])
        let r = PrEngine.detectSessionPrs([set("New Lift", 60, 8), set("New Lift", 65, 8)], b)
        #expect(r.perSet.map(\.mark) == [.baseline, .baseline])
        #expect(r.perSet.allSatisfy { $0.axes.isEmpty })
        #expect(r.prCount == 0)
    }

    @Test("a floor-only key can be beaten — an onboarding 1RM floor is a bar")
    func floorOnlyIsBeatable() {
        let b = PrEngine.buildBaselines(
            [], isTimed: { _ in false }, floorFor: { $0 == "Hack Squat" ? PrFloor(weight: 100, e1rm: 112.5) : nil },
            candidateKeys: ["Hack Squat"]
        )
        let r = PrEngine.detectSessionPrs([set("Hack Squat", 105, 5)], b)
        #expect(r.perSet[0].mark == .axes([.weight, .e1rm]))
        #expect(r.perSet[0].records[.weight]?.previous == 100)
        #expect(r.perSet[0].records[.e1rm]?.previous == 112.5)
    }

    @Test("a warm-up is neither a record nor a baseline mark")
    func warmupIsNothing() {
        let b = PrEngine.buildBaselines([], isTimed: { _ in false }, candidateKeys: ["New Lift"])
        let r = PrEngine.detectSessionPrs([set("New Lift", 40, 10, setType: "warmup")], b)
        #expect(r.perSet[0].mark == .axes([]))
    }

    @Test("baselines cached without provenance keep the old reading: a bar is session-backed, no bar is none")
    func legacyBaselines() throws {
        let json = #"{"bestWeight":[["Old",100]],"bestRepsAtWeight":[],"bestE1rm":[],"bestSeconds":[],"bestSetVolume":[]}"#
        let b = try JSONDecoder().decode(PrBaselines.self, from: json.data(using: .utf8)!)
        #expect(b.provenance.isEmpty)
        let r = PrEngine.detectSessionPrs([set("Old", 105, 5), set("Fresh", 50, 5)], b)
        #expect(r.perSet[0].mark == .axes([.weight]))
        #expect(r.perSet[1].mark == .baseline)
    }

    // MARK: - The founder's Seated Cable Row (Wide Grip), 2026-09-24

    /// Every `workout_sets` row for the movement before Thursday, with the
    /// `est_1rm_kg` the server holds — Epley-era numbers up to 2026-09-10
    /// (42.5 × 12 stored as 59.50), Brzycki from 2026-09-17 (61.20).
    static let wideGripHistory: [BaselineSetRow] = {
        let key = "Seated Cable Row (Wide Grip)"
        let rows: [(Double, Double, Double, String?)] = [
            (35, 12, 49.0, nil), (35, 12, 49.0, nil),            // 07-16
            (35, 12, 49.0, nil), (35, 12, 49.0, nil),            // 07-23
            (35, 12, 49.0, nil), (42.5, 10, 56.7, nil),          // 07-30
            (35, 12, 49.0, nil), (42.5, 11, 58.1, nil),          // 08-06
            (42.5, 10, 56.7, nil), (42.5, 10, 56.7, "failure"),  // 08-13
            (42.5, 11, 58.1, nil), (42.5, 10, 56.7, nil),        // 08-20
            (42.5, 12, 59.5, nil), (42.5, 10, 56.7, nil),        // 08-27 — the first 42.5 × 12
            (42.5, 10, 56.7, nil), (42.5, 10, 56.7, nil),        // 09-03
            (42.5, 12, 59.5, nil), (42.5, 10, 56.7, nil),        // 09-10
            (42.5, 12, 61.2, nil), (42.5, 11, 58.85, nil),       // 09-17
        ]
        return rows.map { BaselineSetRow(key: key, weightKg: $0.0, reps: $0.1, est1rm: $0.2, setType: $0.3) }
    }()

    @Test("Thursday's 50 × 7 wins Weight only: the e1RM bar is 61.2 from the standing 42.5 × 12")
    func wideGripThursday() {
        let key = "Seated Cable Row (Wide Grip)"
        let b = PrEngine.buildBaselines(Self.wideGripHistory, isTimed: { _ in false }, candidateKeys: [key])
        #expect(b.provenance[key] == .sessionBacked)
        #expect(b.bestWeight.first { $0.key == key }?.value == 42.5)
        // Brzycki 42.5 × 36 / 25 = 61.2 — NOT the 59.5 the Epley-era rows
        // store; the ledger's 59.50 is what made 60.0 look like a record.
        #expect(b.bestE1rm.first { $0.key == key }?.value == 61.2)
        #expect(b.bestSetVolume.first { $0.key == key }?.value == 510)

        let r = PrEngine.detectSessionPrs([set(key, 50, 7), set(key, 42.5, 12)], b)
        #expect(r.perSet[0].mark == .axes([.weight]), "50 > 42.5; 60.0 < 61.2; 350 < 510")
        #expect(r.perSet[0].est1rm == 60)
        #expect(r.perSet[1].mark == .axes([]), "42.5 × 12 ties 61.2 and 510 — a tie is not a record")
        #expect(r.prCount == 1)
    }
}
