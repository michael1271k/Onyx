import Foundation
import GRDB
import OnyxCore
import OnyxData

/// Everything the post-workout page draws, assembled in ONE pass off the main
/// actor.
///
/// ── WHY THE WHOLE LEDGER, ONCE ──────────────────────────────────────────────
/// The page asks four questions that all want the same rows: what this session
/// was, what the session before it was, where this split's tonnage has been
/// going, and which sets were records. Reading per question means four passes
/// over overlapping ranges and four chances for them to disagree — the record
/// count in the metric grid differing from the gold points on the chart, say.
/// So the ledger is read once and every number on the screen comes out of that
/// one snapshot.
///
/// It is a few thousand rows and `HistoryWeeks` already reads all of them
/// on every open. When the ledger reaches six figures this becomes a ranged
/// query in `OnyxData`, which Track E owns (plan §10).
extension SessionAnalysis {

    /// One session of this split, on the progression line.
    struct SplitPoint: Identifiable, Sendable, Equatable {
        var id: String { sessionId }
        let sessionId: String
        let date: String
        let tonnageKg: Double
        let prCount: Int
        /// Logged inside a maintenance week (the LEVER, not the deload phase).
        ///
        /// The line drops on these weeks by design — that is what a
        /// maintenance week IS — and a solid point in the middle of a
        /// progression chart reads as a bad session rather than a planned one.
        let isMaintenance: Bool
    }

    struct Page {
        let report: Report
        /// Every session of this split, oldest first.
        let split: [SplitPoint]
        /// This session's place in the CAREER, oldest first.
        ///
        /// ── WHY THIS IS NOT `split.firstIndex` ──────────────────────────────
        /// The band's `#N` was the index within `split`, and `split` is filtered
        /// to one `dayKey`. So a Legs A session logged after 113 workouts read
        /// `#8` — arithmetically correct ("the 8th Legs A") and, printed bare
        /// beside a date and a time, unreadable as anything but "your 8th
        /// workout". It is worse than it looks, too: 74 of the 114 sessions on
        /// record predate `day_key` entirely (the Notion-migrated era, Mar–Jun
        /// 2026), so the per-split index cannot exceed 8 no matter how long the
        /// user trains under it.
        ///
        /// A session that recorded no work at all is not counted and gets no
        /// number — one such shell exists, and numbering it would put a gap in
        /// every number after it.
        let careerIndex: Int?
        /// The previous session of the SAME split. Every delta on the page is
        /// against this and nothing else — comparing a leg day against the
        /// upper day that happened to precede it turns a tonnage delta into
        /// noise with a sign on it.
        let previous: Summary?
        /// The deck that owned the session's date — for the day's name.
        let program: Program?
        /// Active energy, in kcal.
        ///
        /// ── MEASURED WHEN THERE IS A MEASUREMENT ────────────────────────────
        /// This was `Estimates.estimateCalories(…)` unconditionally and
        /// `avgBpm` was the literal `nil`, both written when the local mirror
        /// had no columns to read. It has had `calories_burned`, `avg_bpm`,
        /// `calories_estimated` and `avg_bpm_estimated` since `v11`;
        /// `HealthSync.syncSessionMetrics` fills them from the watch's own
        /// `HKWorkout` and the finish sheet writes them when you type one. So
        /// the summary page was the only screen in the app still guessing, and
        /// it printed `calc` over a figure the watch had measured — the 7
        /// September session has 383 kcal and 122 bpm on the row and showed an
        /// estimate and a dash.
        ///
        /// The estimate remains the fallback, and `caloriesEstimated` is what
        /// the `calc` mark and the provenance line read: a measured figure must
        /// never be labelled as arithmetic.
        let calories: Double?
        /// False only when the store holds a MEASURED figure (the column is
        /// present and `calories_estimated` is 0).
        let caloriesEstimated: Bool
        /// How the estimate was arrived at, when it is one. Nil for a measured
        /// figure and for no figure at all.
        let calorieBasis: CalorieEstimate.Basis?
        /// Average heart rate — the watch's, when it recorded one.
        let avgBpm: Double?
        /// True when `avgBpm` is carried forward rather than measured.
        let avgBpmEstimated: Bool
        /// The tag row: plan, phase week and lever, each resolved FOR THIS
        /// DATE and not for today. A session logged in week 3 of the cut still
        /// says so after the block has moved on.
        let planLabel: String
        let week: WeekPhase?
        let lever: NutritionLever?
        let maintenance: Bool

        /// Tonnage against the previous same-split session. Nil when there is
        /// no comparable session — a reserved line, never a zero.
        var tonnageDelta: Double? {
            guard let previous, previous.tonnageKg > 0 else { return nil }
            return report.tonnageKg - previous.tonnageKg
        }

        var setsDelta: Int? {
            guard let previous else { return nil }
            return report.sets - previous.sets
        }

        /// Minutes against the previous same-split session — and nil rather
        /// than a number when that session's clock cannot be believed.
        ///
        /// `credibleDurationMin` is the test and states the case. The shape
        /// here matches `tonnageDelta` one line up, which has always refused
        /// to divide by a previous session that recorded no tonnage: a delta
        /// is only as good as the thing it is measured from, and the reserved
        /// line is the honest output when that thing is missing.
        var durationDelta: Double? {
            guard let previous, let was = previous.credibleDurationMin,
                  let now = report.session.durationMin else { return nil }
            return now - was
        }

        /// The one sentence worth putting under the title: how this session
        /// stands against every other session of its split.
        ///
        /// ── WHY IT IS NOT THE VERDICT SENTENCE ONE LINE DOWN ────────────────
        /// `verdict` compares against the PREVIOUS session and belongs to the
        /// chart it captions, where the reader is already looking at a line
        /// between two points. This is the other question — not "up on
        /// Tuesday" but "when was the last time it was this heavy" — and it is
        /// the one that makes a page worth opening on purpose.
        ///
        /// Silent unless it has something to say. Three conditions, each of
        /// which exists to stop the line from lying:
        ///
        ///   · four sessions of history, so "heaviest" is a claim and not an
        ///     artefact of a short list;
        ///   · a gap of at least three weeks, because "heaviest in 8 days" is
        ///     a fortnight's noise wearing a headline's clothes;
        ///   · a real tonnage, so a bodyweight or cardio day — which records
        ///     none — says nothing rather than claiming a record of zero.
        ///
        /// The split's NAME is passed in rather than resolved here: the title
        /// at the top of the page resolves it against the environment's active
        /// programme and this type holds the session's own, and a sentence that
        /// called the day something other than the heading three lines above it
        /// would read as being about a different session.
        func headline(_ label: String) -> String? {
            guard let index = split.firstIndex(where: { $0.sessionId == report.session.id }),
                  index >= 3
            else { return nil }
            let current = split[index]
            guard current.tonnageKg > 0 else { return nil }
            guard let beaten = split[..<index].lastIndex(where: { $0.tonnageKg >= current.tonnageKg }) else {
                return "Heaviest \(label) on record."
            }
            guard let from = LogicalDay.date(fromISO: split[beaten].date),
                  let to = LogicalDay.date(fromISO: current.date)
            else { return nil }
            let weeks = Int(to.timeIntervalSince(from) / (7 * 24 * 3600))
            guard weeks >= 3 else { return nil }
            return "Heaviest \(label) in \(weeks) weeks."
        }

        /// The verdict sentence over the Progression chart.
        var verdict: String {
            guard let previous, previous.tonnageKg > 0 else {
                return "First \(SessionAnalysis.dayLabel(report.session.dayKey, in: program) ?? "session") on record."
            }
            let delta = report.tonnageKg - previous.tonnageKg
            let pct = delta / previous.tonnageKg * 100
            let when = LogicalDay.date(fromISO: previous.date).map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? previous.date
            if abs(pct) < 1 { return "Level with \(when)." }
            return delta > 0
                ? "Up \(jsIntegerString(jsRound(abs(pct))))% on \(when)."
                : "Down \(jsIntegerString(jsRound(abs(pct))))% on \(when)."
        }
    }

    /// The page, or nil when the id names nothing.
    static func page(database: AppDatabase, sessionId: String) -> Page? {
        guard let session = try? database.session(id: sessionId),
              let ledger = try? database.historySets(),
              let sessions = try? database.sessionHistory()
        else { return nil }

        let ctx = context(database: database)
        let ladder = (try? database.leverLadder(userId: session.userId)) ?? .empty
        let rows = ledger.filter { $0.sessionId == sessionId }
        let ids = Set(rows.map(\.exerciseId))
        let history = ledger.filter { ids.contains($0.exerciseId) }
        let built = report(session, rows: rows, history: history, in: ctx)

        // The split's line, oldest first. `summaries` replays the whole ledger
        // in order, so a record beaten last month still counts on the session
        // that set it — which is exactly what a gold point on the chart means.
        let everything = summaries(sessions, ledger: ledger, in: ctx)
            .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        let mine = everything.filter { $0.dayKey == session.dayKey }
        let index = mine.firstIndex { $0.id == session.id }

        // The career line. `sets` is the counted-set count `summaries` already
        // computed (ghosts and warm-ups excluded), so "recorded work" is the
        // same test the rest of the page applies rather than a second opinion.
        let career = everything.filter { $0.sets > 0 }
        let careerIndex = career.firstIndex { $0.id == session.id }.map { $0 + 1 }

        let goals: UserGoalRow? = (try? database.read { db in
            try UserGoalRow.filter(Column("user_id") == session.userId).fetchOne(db)
        }) ?? nil
        let lens = MaintenanceLens(ladder: ladder, today: LogicalDay.today())
        let bodyweight: Double? = ((try? database.latestBodyReading(userId: session.userId, before: session.date)) ?? nil)?.weightKg
        let today = LogicalDay.today()

        // What the session row itself holds. A STORED figure wins outright,
        // measured or not: `HealthSync` writes the watch's own active energy,
        // and where it could only estimate it estimated from your recent
        // sessions, which beats a MET table applied to a duration. The
        // `*_estimated` flags travel with the number so the cell can say which
        // it is. The MET estimate is reached only when the column is null.
        let storedKcal = session.caloriesBurned.map(Double.init)
        let estimate = Estimates.estimateCalories(
            durationMin: session.durationMin, samples: [], bodyweightKg: bodyweight
        )

        return Page(
            report: built,
            split: mine.map {
                SplitPoint(
                    sessionId: $0.id, date: $0.date, tonnageKg: $0.tonnageKg,
                    prCount: $0.prCount, isMaintenance: lens.callsIt($0.date)
                )
            },
            careerIndex: careerIndex,
            previous: index.flatMap { $0 > 0 ? mine[$0 - 1] : nil },
            program: ctx.program(on: session.date),
            calories: storedKcal ?? estimate?.kcal,
            caloriesEstimated: storedKcal == nil ? true : session.caloriesEstimated,
            calorieBasis: storedKcal == nil ? estimate?.basis : nil,
            avgBpm: session.avgBpm.map(Double.init),
            avgBpmEstimated: session.avgBpmEstimated,
            planLabel: ctx.schedule.plans.first { $0.id == Schedule.planId(owning: session.date, in: ctx.schedule) }?.label
                ?? ctx.schedule.programId,
            week: Phases.weekPhase(
                weekStart: Week.start(of: session.date, startDay: Week.startDay(fromEndDay: goals?.weekEndDay)),
                in: ctx.schedule.phases
            ),
            lever: Levers.leverForDate(session.date, today: today, in: ladder).flatMap { Levers.lever(byId: $0, in: ladder) },
            maintenance: Maintenance.isMaintenanceDate(session.date, today: today, ladder: ladder, phases: ctx.schedule.phases)
        )
    }

    /// Session-best estimated 1RM per exercise across every session it appears
    /// in — the 40×16 sparkline in a ledger header, and the Library's rows.
    ///
    /// Returns the values only: a sparkline has no axis, so the dates are not
    /// wanted and carrying them would invite somebody to label one.
    static func sparkline(_ rows: [HistorySetRow]) -> [Double] {
        sessionMeanE1rm(rows).map(\.kg)
    }
}
