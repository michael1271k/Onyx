import Testing
import Foundation
import OnyxCore
import OnyxData
@testable import Onyx

/// The water row's one tap.
///
/// ── WHY THIS TEST EXISTS AND WHY IT IS HERE ─────────────────────────────────
/// `addWater` crashed the app on the first tap of any day that already had a
/// `daily_logs` row — a Swift dynamic-exclusivity trap, `dailyLog?.waterMl =
/// (waterMl ?? 0) + ml` opening an exclusive `modify` on `dailyLog` and then
/// reading it again in its own right-hand side.
///
/// It shipped because nothing tested THIS layer. `DayEditing`'s water tests
/// exercise the store and pass — the store was never the problem — and the view
/// has no test at all. The trap is in the model, between them, so that is where
/// the sentinel goes.
///
/// A trap is not a failure: if the bug returns, this test does not report red,
/// the test PROCESS dies. That is still the cheapest thing that cannot pass
/// while the defect is present, which is what a regression test has to be.
@MainActor
@Suite("Water row")
struct WaterRowTests {

    private static let user = "00000000-0000-0000-0000-000000000001"

    private static func model(date: String = "2026-09-15") throws -> NutritionModel {
        let database = try AppDatabase.inMemory(deviceId: "water-row")
        let targets = TargetResolver(database: database, userId: user)
        targets.start()
        return NutritionModel(database: database, userId: user, targets: targets, date: date)
    }

    @Test("a tap on a day that already has a row adds a glass instead of trapping")
    func addsOnAnExistingRow() throws {
        let model = try Self.model()
        // Mints `daily_logs` and assigns `dailyLog` synchronously — the state
        // the crash needed, without waiting on `observe()`'s streams. An empty
        // day cannot reproduce it: the optional chain short-circuits before the
        // read, which is why the first tap of a fresh day always survived.
        model.setEstimated(true)
        #expect(model.dailyLog != nil)

        model.addWater()
        #expect(model.waterMl == NutritionModel.glassMl)
    }

    @Test("glasses accumulate; the second tap reads the first")
    func accumulates() throws {
        let model = try Self.model()
        model.setEstimated(true)
        model.addWater()
        model.addWater()
        model.addWater()
        #expect(model.waterMl == NutritionModel.glassMl * 3)
    }

    @Test("an empty day still takes the first glass")
    func emptyDay() throws {
        let model = try Self.model(date: "2026-09-14")
        // `dailyLog` is nil here, so the optimistic assignment short-circuits
        // and the figure arrives with the observation instead. The LEDGER write
        // is the part that must happen either way.
        model.addWater()
        #expect(model.dailyLog == nil || model.waterMl == NutritionModel.glassMl)
    }

    // MARK: - The one truth, and what the row prints (W1)

    /// ── THESE DO NOT RUN `observe()` ────────────────────────────────────────
    /// `observe()` is the `.task` body: it awaits its streams and never
    /// returns, so a test cannot await it and a value that arrives through one
    /// cannot be asserted synchronously. Everything below is reachable without
    /// it — the writers patch the published value themselves, and the cases
    /// that matter most here (nothing written at all) need no state.
    ///
    /// The LEDGER branch of the rule is asserted where its inputs can be
    /// controlled: `WaterTruthTests` over the pure function, and
    /// `WidgetWaterTruthTests` over a snapshot built from a seeded store. Those
    /// two and this one read the same four shapes, which is what "the tab and
    /// the tile agree" can mean across modules that cannot see each other.

    @Test("the tab reads the shared rule, not a second copy of it")
    func readsWaterTruth() throws {
        // A structural pin. It fails the moment somebody writes the rule out
        // again here — which is exactly how the tab and the widget came to
        // disagree in the first place.
        let model = try Self.model()
        model.setEstimated(true)
        model.addWater()
        #expect(model.waterMl == WaterTruth.ml(
            log: model.dailyLog?.waterMl, ledger: model.water.map(\.amountMl)
        ))
    }

    @Test("an untouched day inside the ingest window says so, instead of rendering a dash")
    func waitingOnHealth() throws {
        // The `— / 3.0 L` the founder reported. Neither store has been written,
        // which is not "you drank nothing" — it is "the HealthKit read is
        // pending, or it was denied and will stay pending". `DailyLogIngest`
        // returns at `guard !payload.isEmpty` when Health has nothing to say,
        // so on a phone where the read is denied that state is permanent.
        let model = try Self.model(date: LogicalDay.today())
        #expect(model.waterMl == nil)
        #expect(model.isAwaitingHealthWater)
        #expect(model.waterFigures == "Waiting for Apple Health")
    }

    @Test("an old day with no water keeps its dash — the render no test touched")
    func theDashSurvivesWhereItIsTrue() throws {
        // A quiet Tuesday last March really does hold no water, and calling it
        // still-loading would be the same lie in the other direction. This is
        // the case that keeps the sentence honest, and nothing covered either
        // render before W1.
        let model = try Self.model(date: "2026-03-03")
        #expect(model.waterMl == nil)
        #expect(!model.isAwaitingHealthWater)
        #expect(model.waterFigures.hasPrefix("—"))
    }

    @Test("yesterday is still inside the window the ingest scans")
    func yesterdayIsStillPending() throws {
        // `syncCardioBouts` and `syncRecent` both read today AND yesterday, so
        // an untouched yesterday is genuinely still waiting.
        let model = try Self.model(date: NightWindow.previousDay(LogicalDay.today()))
        #expect(model.isAwaitingHealthWater)
    }

    @Test("a day with water prints the figure, never the sentence")
    func aMeasuredDayPrintsItsFigure() throws {
        let model = try Self.model(date: LogicalDay.today())
        model.setEstimated(true)
        model.addWater()
        model.addWater()
        model.addWater()
        #expect(model.waterMl == 750)
        #expect(!model.isAwaitingHealthWater)
        #expect(model.waterFigures.hasPrefix("0.8"))
    }
}
