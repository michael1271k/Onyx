import Testing
import Foundation
import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData
@testable import Onyx

/// W4's four claims that no screenshot can make.
///
/// A shot of the shelf shows the weeks that ARE on it and says nothing about
/// the one that is not. A shot of a cut block cannot show that a deload would
/// be drawn in another hue. A shot of a pushed page looks very like a shot of a
/// sheet at `.large`. And a rail is a bar: it is exactly as convincing at 74 %
/// when the number behind it is wrong.
@MainActor
@Suite("Weekly report (W4)")
struct WeeklyReportTests {

    // MARK: - GOAL 1 · the anchor week reaches the shelf

    /// `WorkoutWeek.pastWeeks` emitting Week 0 is asserted in
    /// `WorkoutWeekTests`; this is the half below it. `blocks(_:)` is the
    /// function that turns the walk's weeks into what is DRAWN, by joining them
    /// against `Phases.enumerateWeeks` — so a week the walk emitted can still
    /// fail to appear here, which is the only place it could have gone missing.
    @Test("Week 0 reaches the shelf, in a block with a phase of its own")
    func weekZeroIsBanneredAndTinted() async throws {
        let environment = HistoryPreviews.environment()
        let week = WorkoutWeek(
            database: environment.database, userId: environment.userIdString,
            phase: .cut, seededToday: "2026-09-03", seededDayKey: "cb_a"
        )
        let library = await week.library()
        let blocks = PastWeeksLibrary.blocks(library)

        let owner = try #require(
            blocks.first { $0.weeks.contains { $0.weekStart == "2026-07-12" } },
            "the anchor week is on no block of the shelf: \(blocks.map(\.eraTag))"
        )
        let zero = try #require(owner.weeks.first { $0.weekStart == "2026-07-12" })
        #expect(zero.label == "Week 0")
        // A phase of its OWN, not the orphan bucket: `kind` is nil only for the
        // "Between blocks" section, and a Week 0 filed there draws grey under a
        // heading that reads like an error.
        #expect(owner.kind != nil)
        #expect(owner.id != "unblocked")

        // Nothing on the shelf predates the anchor. The PPL era is a different
        // plan and stays out — `Schedule.isPlannable` is the gate and W4 kept it.
        #expect(blocks.allSatisfy { $0.weeks.allSatisfy { $0.weekStart >= "2026-07-12" } })
    }

    // MARK: - GOAL 2 · the wash follows the phase

    /// The banner's wash and its label take `Self.tint(kind)`, so this is the
    /// whole of the claim: four kinds, four inks, and one grey for the week no
    /// block claims.
    @Test("a banner's hue follows its PhaseKind, and an unclaimed week is grey")
    func bannerHueFollowsPhase() {
        let inks = PhaseKind.allCases.map { PastWeeksLibrary.tint($0) }
        #expect(Set(inks).count == PhaseKind.allCases.count, "two phases share an ink")
        for kind in PhaseKind.allCases {
            #expect(PastWeeksLibrary.tint(kind) == Color.onyx.phase(kind))
        }
        #expect(PastWeeksLibrary.tint(nil) == Color.onyx.textTertiary)
        // And the grey is not one of the four, or "no phase" would read as one.
        #expect(!inks.contains(Color.onyx.textTertiary))
    }

    // MARK: - GOAL 3 · all four doors moved

    /// The four doors, read off the SOURCE.
    ///
    /// ── WHY A FILE READ AND NOT A VIEW ASSERTION ────────────────────────────
    /// "This binding opens a push and not a sheet" is a fact about a view
    /// modifier, and a `View` cannot be interrogated for its modifiers. The
    /// alternative — a shot per door — is four photographs that all look like a
    /// sheet at `.large`, which is exactly the failure this wave was called in
    /// to fix.
    ///
    /// ── AND WHY IT CANNOT PASS VACUOUSLY (W8) ───────────────────────────────
    /// A file-walk test that cannot find its files silently asserts nothing.
    /// `#filePath` is baked at compile time and a simulator reads the host's
    /// disk, so the path resolves — and the FIRST expectation is that every one
    /// of the four was read and is not empty. A missing file fails the test
    /// rather than skipping it.
    @Test("every door pushes WeekReportView, and none of them presents a sheet")
    func fourDoorsPushAndNonePresents() throws {
        let root = URL(fileURLWithPath: #filePath)     // …/native/OnyxTests/<this>.swift
            .deletingLastPathComponent()               // …/native/OnyxTests
            .deletingLastPathComponent()               // …/native
            .appendingPathComponent("Onyx/Features")

        let doors: [(path: String, binding: String)] = [
            ("Workout/WorkoutTabView.swift", "wrapped"),
            ("Workout/PastWeeksLibrary.swift", "opened"),
            ("History/WeekDaysView.swift", "wrapDoor"),
            ("Today/TodayTabView.swift", "wrapDoor"),
        ]

        for door in doors {
            let source = try #require(
                try? String(contentsOf: root.appendingPathComponent(door.path), encoding: .utf8),
                "could not read \(door.path) — this test asserts nothing without it"
            )
            #expect(source.count > 1_000, "\(door.path) came back empty")
            #expect(
                source.contains("navigationDestination(item: $\(door.binding))"),
                "\(door.path) does not push $\(door.binding)"
            )
            #expect(
                !source.contains("sheet(item: $\(door.binding))"),
                "\(door.path) still presents $\(door.binding) as a sheet"
            )
            #expect(source.contains("WeekReportView("), "\(door.path) reaches no report")
            // The sheet and the ring are gone from the tree, not merely unused.
            #expect(!source.contains("WeeklyWrapView("))
            #expect(!source.contains("WeeklyMuscleRing("))
        }
    }

    // MARK: - GOAL 4 · the report summarises what it claims to

    /// ── MOSTLY MOVED TO `swift:data` (W8) ───────────────────────────────────
    /// `WeekReport` is an OnyxData type now, and `WeekReportTests` asserts
    /// every fold against the payload field it claims to summarise — in a suite
    /// `npm run check` actually runs, which this one is not. What is left here
    /// is the half that needs the APP: the preview environment's store, and the
    /// empty user id the harness signs in with.
    @Test("the report builds off the preview store, through the empty-user fallback")
    func theReportBuildsInTheHarness() throws {
        let environment = HistoryPreviews.environment()
        let database = environment.database
        let userId = database.localUserId()
        let weekStart = "2026-08-16"          // the one week this seed closed complete

        let summary = try #require(
            WorkoutWeek.wrap(database, userId: userId, weekStart: weekStart)
        )
        let context = try #require(try? database.scheduleContext(userId: userId, today: weekStart))
        let planned = Schedule.sessionTargetIn(context)
        #expect(planned > 0, "a plan with no training days has no session count to report")

        // Cross-wave law 16: `AppEnvironment.userIdString` is "" in the harness
        // and in every preview, and an export built for "" comes back with
        // seven empty days.
        let report = try #require(
            WeekReport.build(
                database: database, userId: "", summary: summary,
                plannedSessions: planned, today: "2026-09-03"
            )
        )
        #expect(report.sessions == summary.sessions)
        #expect(report.plannedSessions == planned)
        #expect(report.adherence.count == 7, "the fallback read an empty week")
        #expect(report.rangeLabel.contains("–"), "the range label did not survive the move to OnyxCore")
        #expect(report.topRecords.count <= WeekReport.recordCap)
    }
}
