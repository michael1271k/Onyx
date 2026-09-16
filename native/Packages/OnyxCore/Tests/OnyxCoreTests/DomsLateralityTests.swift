import Foundation
import Testing
@testable import OnyxCore

/// Laterality, on the two things in OnyxCore that could break silently: the
/// export token and the scoring fold.
///
/// ── WHY BYTE-IDENTITY IS THE ASSERTION AND NOT "LOOKS RIGHT" ─────────────────
/// `weekly-export.json` is a golden document, and three of its cases were
/// written before `doms_logs` had a `side` column. If a whole-muscle rating
/// started rendering as `Quads@B` or `Quads/` or `Quads both`, those goldens
/// would fail — and the correct response would NOT be to regenerate them. The
/// grammar promises that an absent side and an absent sub-region add nothing at
/// all, so the token for a rating written in August is the token for the same
/// rating written today. These tests are that promise, stated where it fails
/// loudly rather than where it fails as a diff nobody reads.
@Suite("Soreness laterality — the token and the fold")
struct DomsLateralityTests {

    private func rating(
        _ muscle: String, _ severity: Double, side: String? = nil, subRegion: String? = nil,
        date: String = "2026-09-16"
    ) -> ExportDoms {
        ExportDoms(
            date: date, muscle: muscle, severity: severity,
            sourceLabel: nil, sourceDate: nil, side: side, subRegion: subRegion
        )
    }

    // MARK: - The token

    @Test("a bilateral whole-muscle token is the bare muscle name, exactly as v1 wrote it")
    func bilateralTokenIsV1() {
        #expect(WeeklyExport.domsName(rating("Quads", 2)) == "Quads")
        // And the two spellings of "no side" agree, because a row that came
        // back from the server after the founder's SQL landed may carry the
        // word rather than a NULL.
        #expect(WeeklyExport.domsName(rating("Quads", 2, side: "both")) == "Quads")
        // An empty sub-region is the same absence, and must not leave a slash
        // behind — `Quads/` would be a token no parser could read back.
        #expect(WeeklyExport.domsName(rating("Quads", 2, subRegion: "")) == "Quads")
    }

    @Test("a side becomes @L or @R, and a sub-region a slash — in that order")
    func lateralTokens() {
        #expect(WeeklyExport.domsName(rating("Glutes", 3, side: "right")) == "Glutes@R")
        #expect(WeeklyExport.domsName(rating("Arms", 1, side: "left")) == "Arms@L")
        #expect(WeeklyExport.domsName(rating("Back", 2, subRegion: "Erectors")) == "Back/Erectors")
        #expect(WeeklyExport.domsName(rating("Arms", 2, side: "left", subRegion: "Triceps")) == "Arms/Triceps@L")
    }

    @Test("the marker is a suffix because a sub-region can begin with L")
    func lMarkerIsNotAPrefix() {
        // `Lats` is a sub-region of `Back`. A LEADING L/R marker — how the
        // SESSIONS section spells a unilateral set — makes `L Back/Lats`
        // ambiguous against a sub-region whose name starts with the marker.
        // The `@` suffix cannot collide, because `@` occurs in no muscle or
        // sub-region name in either vocabulary.
        #expect(WeeklyExport.domsName(rating("Back", 2, subRegion: "Lats")) == "Back/Lats")
        #expect(WeeklyExport.domsName(rating("Back", 2, side: "left", subRegion: "Lats")) == "Back/Lats@L")
        for name in DomsMuscles.all + DomsMuscles.subRegions.values.flatMap({ $0 }) {
            #expect(!name.contains("@") && !name.contains("/"))
        }
    }

    // MARK: - The fold

    @Test("a left and a right rating fold to the max, so the battery cannot move")
    func foldTakesMaxWithinAMuscle() {
        // The whole migration rests on this. `foldDomsSeverity` is mean across
        // DISTINCT muscles, max within one — so splitting "quads: 3" into
        // "left quad 3, right quad 1" is the same day's soreness, and every
        // battery vector stays where it was.
        let whole = Derived.foldDomsSeverity([rating("Quads", 3)])
        let split = Derived.foldDomsSeverity([
            rating("Quads", 3, side: "left"), rating("Quads", 1, side: "right"),
        ])
        #expect(whole == 3)
        #expect(split == whole)

        // And a sided pair does not count as two muscles in the MEAN either —
        // which is the failure that would have moved every vector.
        let twoMuscles = Derived.foldDomsSeverity([rating("Quads", 3), rating("Chest", 1)])
        let splitPlusOne = Derived.foldDomsSeverity([
            rating("Quads", 3, side: "left"), rating("Quads", 3, side: "right"), rating("Chest", 1),
        ])
        #expect(twoMuscles == 2)
        #expect(splitPlusOne == twoMuscles)
    }

    @Test("a sub-region rating still folds under its parent muscle")
    func subRegionsFoldToTheParent() {
        // The severity is keyed on `muscle`, which is always one of the ten.
        // A sub-region is a detail carried alongside, never a key — so three
        // parts of one back are one back.
        let folded = Derived.foldDomsSeverity([
            rating("Back", 1, subRegion: "Traps"),
            rating("Back", 3, subRegion: "Erectors"),
            rating("Back", 2, side: "left", subRegion: "Lats"),
        ])
        #expect(folded == 3)
        // Every sub-region's parent is one of the recognised ten, so none of
        // them can be a rating the fold silently drops.
        for (parent, subs) in DomsMuscles.subRegions {
            #expect(DomsMuscles.recognised.contains(parent))
            for sub in subs { #expect(DomsMuscles.parentOfSubRegion[sub] == parent) }
        }
    }

    @Test("an unrecognised muscle is still dropped, side or no side")
    func unrecognisedRowsNeverScore() {
        // The rule `DomsMuscles.recognised` exists for: a row nobody can read
        // back must not be able to move the battery. A side does not make one
        // readable.
        #expect(Derived.foldDomsSeverity([rating("Neck", 3, side: "left")]) == nil)
        #expect(Derived.foldDomsSeverity([rating("Knee", 3)]) == nil)
        // Joints are not muscles and never become them (W9 task 7).
        for joint in DomsMuscles.joints { #expect(!DomsMuscles.recognised.contains(joint)) }
    }
}
