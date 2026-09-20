import Foundation
import Testing
@testable import OnyxCore

@Suite("Prescriptions — the paste, the version, the window")
struct PrescriptionPasteTests {

    /// The shape the coach's "W10 plan" table arrives in.
    @Test("a headed markdown table maps every column")
    func headedTable() {
        let block = """
        | Exercise | Load (kg) | Sets | Rep range | RPE cap | Lead rule | Notes |
        |---|---:|---:|---|---:|---|---|
        | Incline DB Press | 34 | 3 | 8–12 | 8 | ALTERNATE | keep the elbows tucked |
        | Lat Pulldown | 50 | 3 | 10–12 | 9 | NONE | |
        | RDL | 40 | 3 | 6–8 | 8 | NONE | hinge, no squat |
        """
        let out = PrescriptionPaste.parse(block, effectiveFrom: "2026-09-15")
        #expect(out.rows.count == 3)
        #expect(out.skipped.isEmpty)
        let incline = out.rows[0]
        #expect(incline.exercise == "Incline DB Press")
        #expect(incline.loadKg == 34)
        #expect(incline.sets == 3)
        #expect(incline.repRange == "8–12")
        #expect(incline.rpeCap == 8)
        #expect(incline.leadRule == .alternate)
        #expect(incline.structure == .straight)
        #expect(incline.notes == "keep the elbows tucked")
        #expect(out.rows[1].loadKg == 50)
        #expect(out.rows[2].repRange == "6–8")
    }

    /// The "Lifting Actions" shape — a movement and a sentence. The load lives
    /// in the prose and nothing but a scan can find it.
    @Test("an action table finds the load in the prose")
    func actionTable() {
        let block = """
        | Movement | Action |
        |---|---|
        | Lat Pulldown | Take it to 50 kg for 3 × 10–12, cap RPE 9 |
        """
        let out = PrescriptionPaste.parse(block, effectiveFrom: "2026-09-15")
        #expect(out.rows.count == 1)
        #expect(out.rows[0].loadKg == 50)
        #expect(out.rows[0].sets == 3)
        #expect(out.rows[0].repRange == "10–12")
        #expect(out.rows[0].rpeCap == 9)
    }

    @Test("a top set and its back-offs keep every load, in order")
    func topSetBackoff() {
        let block = "| Exercise | Load | Sets |\n|---|---|---|\n| Chest Press | 42.5 / 37.5 × 2 | 3 |"
        let out = PrescriptionPaste.parse(block, effectiveFrom: "2026-09-15")
        #expect(out.rows.count == 1)
        let p = out.rows[0]
        #expect(p.structure == .topsetBackoff)
        #expect(p.setLoads == [42.5, 37.5, 37.5])
        // The comparison load is the TOP SET, never an average of the ladder.
        #expect(p.referenceLoadKg == 42.5)
    }

    @Test("a freeform line is read, and a heading is not")
    func freeform() {
        let block = """
        ## Week 10 — lifting
        Incline DB Press — 34 kg × 3 × 8–12 @8, alternate
        Everything else holds.
        """
        let out = PrescriptionPaste.parse(block, effectiveFrom: "2026-09-15")
        #expect(out.rows.count == 1)
        #expect(out.rows[0].exercise == "Incline DB Press")
        #expect(out.rows[0].loadKg == 34)
        #expect(out.rows[0].sets == 3)
        #expect(out.rows[0].repRange == "8–12")
        #expect(out.rows[0].rpeCap == 8)
        #expect(out.rows[0].leadRule == .alternate)
        // "Everything else holds." carries no figure, so it is prose and not a
        // refusal — the screen must not show it as something that failed.
        #expect(out.skipped.isEmpty)
    }

    @Test("a row with no load lands anyway and says so")
    func warnsRatherThanDrops() {
        let block = "| Exercise | Sets | Rep range |\n|---|---|---|\n| Plank | 3 | 45s |"
        let out = PrescriptionPaste.parse(block, effectiveFrom: "2026-09-15")
        #expect(out.rows.count == 1)
        #expect(out.rows[0].loadKg == nil)
        #expect(out.rows[0].repRange == "45s")
        #expect(out.warnings.contains("Plank — no load"))
    }

    // MARK: - Resolution

    @Test("current is the latest version in force, and a future one is not applied")
    func currentVersion() {
        let all = [
            Prescription(exercise: "RDL", loadKg: 30, effectiveFrom: "2026-07-01", version: 1),
            Prescription(exercise: "RDL", loadKg: 40, effectiveFrom: "2026-09-15", version: 2),
            Prescription(exercise: "RDL", loadKg: 45, effectiveFrom: "2026-09-29", version: 3),
        ]
        #expect(Prescriptions.current(all, on: "2026-09-20")["RDL"]?.loadKg == 40)
        #expect(Prescriptions.current(all, on: "2026-07-10")["RDL"]?.loadKg == 30)
        #expect(Prescriptions.current(all, on: "2026-06-01")["RDL"] == nil)
        // Two versions dated the same day: the later WRITE wins.
        let sameDay = [
            Prescription(exercise: "RDL", loadKg: 40, effectiveFrom: "2026-09-15", version: 2),
            Prescription(exercise: "RDL", loadKg: 42, effectiveFrom: "2026-09-15", version: 3),
        ]
        #expect(Prescriptions.current(sameDay, on: "2026-09-20")["RDL"]?.loadKg == 42)
    }

    @Test("a rep window is a window — inside it the delta is zero")
    func repWindow() {
        let w = Prescriptions.repBounds("8–12")!
        #expect(w.floor == 8 && w.ceiling == 12)
        #expect(Prescriptions.repDelta(10, window: w) == 0)
        #expect(Prescriptions.repDelta(8, window: w) == 0)
        #expect(Prescriptions.repDelta(13, window: w) == 1)
        #expect(Prescriptions.repDelta(6, window: w) == -2)
        #expect(Prescriptions.repBounds("6")?.floor == 6)
        #expect(Prescriptions.repBounds("6")?.ceiling == 6)
        // A HOLD is not a rep count and has no window.
        #expect(Prescriptions.repBounds("45s") == nil)
        #expect(Prescriptions.repBounds(nil) == nil)
    }
}
