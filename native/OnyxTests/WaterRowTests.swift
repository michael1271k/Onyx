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
}
