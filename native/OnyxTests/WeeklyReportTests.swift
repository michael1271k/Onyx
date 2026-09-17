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
    @Test("every door pushes WeeklyReportView, and none of them presents a sheet")
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
            #expect(source.contains("WeeklyReportView("), "\(door.path) reaches no report")
            // The sheet and the ring are gone from the tree, not merely unused.
            #expect(!source.contains("WeeklyWrapView("))
            #expect(!source.contains("WeeklyMuscleRing("))
        }
    }

    // MARK: - GOAL 4 · the rails summarise what they claim to

    /// Each rail against the source it names, read out of the same payload the
    /// page reads — not out of a second query, which is the whole point of
    /// there being one call.
    @Test("the three rails agree with the sources they claim to summarise")
    func railsAgreeWithTheirSources() throws {
        let environment = HistoryPreviews.environment()
        let database = environment.database
        let userId = database.localUserId()
        let weekStart = "2026-08-16"          // the one week this seed closed complete

        let summary = try #require(
            WorkoutWeek.wrap(database, userId: userId, weekStart: weekStart)
        )
        let context = try #require(try? database.scheduleContext(userId: userId, today: weekStart))
        let planned = Schedule.sessionTargetIn(context)
        #expect(planned > 0, "a plan with no training days has no Training rail to check")

        let input = try WeeklyExportBuilder(database: database, userId: userId)
            .input(weekStart: weekStart, today: "2026-09-03")
        let report = try #require(
            WeekReport.build(
                database: database, userId: userId, summary: summary,
                plannedSessions: planned, today: "2026-09-03"
            )
        )

        // ── TRAINING: sessions against the plan's own count ─────────────────
        #expect(report.trainingPct == Double(summary.sessions) / Double(planned) * 100)
        #expect(report.trainingDetail.contains("\(summary.sessions) of \(planned)"))

        // ── NUTRITION: `MacroAdherenceSeries`, its ±10 % tolerance, and the
        //    rung in force ON EACH DATE ──────────────────────────────────────
        var targets: [String: AdherenceTargets] = [:]
        for period in input.targetPeriods ?? [] {
            for date in period.dates {
                targets[date] = AdherenceTargets(
                    kcal: period.goals.calorie, protein: period.goals.protein,
                    carbs: period.goals.carbs, fat: period.goals.fat
                )
            }
        }
        let expected = MacroAdherenceSeries.build(
            input.days.map {
                AdherenceDayIn(
                    date: $0.date, kcal: $0.calories, proteinG: $0.proteinG,
                    carbsG: $0.carbsG, fatG: $0.fatG,
                    exception: $0.nutritionException, estimated: $0.nutritionEstimated
                )
            },
            targets: targets, endingOn: input.weekEnd, limit: 7
        )
        #expect(report.adherence == expected, "the strip is not the series it claims to be")
        let graded = expected.filter { $0.verdict == .hit || $0.verdict == .miss }
        let hits = expected.filter { $0.verdict == .hit }.count
        #expect(
            report.nutritionPct == (graded.isEmpty ? nil : Double(hits) / Double(graded.count) * 100)
        )
        // An exception day is neither a hit nor a miss — counting it as a miss
        // is the one arithmetic error this rail can make.
        #expect(!graded.contains { $0.verdict == .exception })

        // ── RECOVERY: the STORED battery, not a recomputed one ──────────────
        let battery = input.days.compactMap(\.batteryPct)
        #expect(
            report.recoveryPct == (battery.isEmpty ? nil : battery.reduce(0, +) / Double(battery.count))
        )
        #expect(report.recoveryDetail.contains(battery.isEmpty ? "no night" : "\(battery.count) night"))

        // ── And the page's own two lists come off the same payload ──────────
        #expect(report.records.map(\.name) == report.records.map(\.name).sorted(), "records are not by exercise")
        #expect(report.records.count == input.sessions.flatMap(\.prs).count)
        #expect(report.waterGoalMl == input.waterGoalMl)
    }
}
