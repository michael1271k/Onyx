#if DEBUG
import SwiftUI
import OnyxCore
import OnyxData

/// The Nutrition tab's photographed states, seeded through the same write paths
/// the app uses — so a preview that renders is also a smoke test of
/// `DayEditing`, and a change to a writer shows up in the screenshot diff.
///
/// ── WHY ONE ENTRY PER DAY AND NOT TWO ───────────────────────────────────────
/// Both public writers for `nutrition_entries` — the HealthKit `ingest` and
/// `setManualMacros` — target the single `daily` row for the date, which is also
/// what a real day holds: HealthKit lands one row per day. A second, per-meal
/// row has no public write path, and inventing one for a screenshot would mean a
/// `OnyxData` API nobody else needs.
///
/// ── WHY THE WEEK IS SEEDED TOO ──────────────────────────────────────────────
/// The adherence dots and the seven-day strip are half the screen, and a shot
/// with six empty columns photographs the empty state of a component rather than
/// the component. The six days behind today carry a hit, a miss, a declared
/// exception, an estimated day and one day with nothing at all — every dot
/// colour the strip can draw, in one picture.
enum NutritionPreviews {

    static let userId = "00000000-0000-0000-0000-000000000001"

    /// `fuel` — an ordinary day under target. `fuel-over` — calories and protein
    /// over (fat under), carbohydrate untracked by a day override, flagged
    /// Social. `fuel-empty` — nothing logged; every figure is an em dash.
    @MainActor
    static func model(_ screen: String) -> NutritionModel? {
        let database = try! AppDatabase.inMemory(deviceId: "shot")
        // The catalogue as rows (W2): decks, plans, phases, rungs.
        PreviewCatalogue.seed(database)
        let date = LogicalDay.today()
        _ = try? database.editUserGoals(userId: userId) { row in
            row.calorieGoal = 1955
            row.proteinGoalG = 170
            row.carbsGoalG = 195
            row.fatGoalG = 55
            row.stepsGoal = 10000
            row.waterGoalMl = 3000
            row.activeLever = "custom"
            row.activePlan = "onyx5"
            row.activePhase = ProgramPhase.cut.rawValue
            row.goalPreset = ProgramPhase.cut.rawValue
        }

        switch screen {
        case "fuel-empty":
            break
        default:
            seedWeek(database, endingOn: date)
        }

        switch screen {
        case "fuel", "nutrients", "macro-edit", "fuel-calendar":
            _ = try? database.ingest(
                HealthPayload(date: date, values: [
                    .calories: 1420, .protein: 128, .carbs: 140, .fats: 42, .water: 1800,
                    .fiber: 24, .sugar: 31, .sodium: 2450, .potassium: 2600, .calcium: 820,
                    .iron: 11, .magnesium: 310, .vitaminC: 74, .vitaminD: 45, .satFat: 14,
                ]),
                userId: userId
            )
        case "fuel-over":
            _ = try? database.ingest(
                HealthPayload(date: date, values: [.calories: 2150, .protein: 175, .carbs: 180, .fats: 48, .water: 2400]),
                userId: userId
            )
            _ = try? database.editDailyLog(userId: userId, date: date) { $0.nutritionException = "Social" }
            _ = try? database.setDailyTarget(userId: userId, date: date) { row in
                row.kcal = 1800
                row.proteinG = 150
                row.fatG = 55
                row.trackCarbs = false
                row.note = "Dinner out"
            }
        case "fuel-empty":
            break
        default:
            return nil
        }
        let targets = TargetResolver(database: database, userId: userId)
        targets.start()
        return NutritionModel(database: database, userId: userId, targets: targets, date: date)
    }

    /// The six days before `date`: `nil` means a day nobody logged.
    private static let history: [(kcal: Double, protein: Double, carbs: Double, fats: Double)?] = [
        (1_890, 168, 178, 52),
        (2_310, 152, 240, 68),
        nil,
        (1_940, 174, 182, 49),
        (1_820, 171, 165, 47),
        (2_040, 166, 196, 55),
    ]

    @MainActor
    private static func seedWeek(_ database: AppDatabase, endingOn date: String) {
        for (offset, day) in history.enumerated() {
            guard let day, let iso = ISODate.addDays(date, offset - 6) else { continue }
            _ = try? database.ingest(
                HealthPayload(date: iso, values: [
                    .calories: day.kcal, .protein: day.protein, .carbs: day.carbs,
                    .fats: day.fats, .water: 2_400,
                ]),
                userId: userId
            )
            // The blow-out five days back was a declared meal out; the day
            // before yesterday was eyeballed rather than weighed.
            if offset == 1 {
                _ = try? database.editDailyLog(userId: userId, date: iso) { $0.nutritionException = "Event" }
            }
            if offset == 4 {
                _ = try? database.editDailyLog(userId: userId, date: iso) { $0.nutritionEstimated = true }
            }
        }
    }

    @MainActor
    static func view(_ screen: String) -> some View {
        Harness(screen: screen).environment(AppEnvironment.preview)
    }
}

/// The model is built ONCE, in `@State`.
///
/// ── THE BUG THIS EXISTS TO PREVENT ──────────────────────────────────────────
/// `model(_:)` seeds a fresh in-memory database every time it is called, so
/// building it inside a `@ViewBuilder` hands a NEW, unobserved model to every
/// body evaluation. `NutritionTabView` pins the first one in its own `@State`
/// and so looked fine — but anything else in the same tree (a sheet, a pushed
/// screen) got a fresh empty store on the second pass, and photographed a
/// screen of zeros beside a tab showing the real day.
private struct Harness: View {
    let screen: String

    @State private var model: NutritionModel?

    var body: some View {
        Group {
            if let model {
                switch screen {
                case "nutrients":
                    NavigationStack { NutrientsView(model: model) }
                // The fourth sheet, on the same terms as `macro-edit` above:
                // presented by the harness, not by a door inside the tab.
                case "fuel-calendar":
                    NavigationStack { NutritionTabView(seeded: model) }
                        .sheet(isPresented: .constant(true)) { DayPickerSheet(model: model) }
                case "macro-edit":
                    // Presented BY the harness rather than by a debug flag
                    // inside the tab: a screen that ships a way to open one of
                    // its sheets for a screenshot is a screen with a state
                    // nobody can reach and nobody maintains.
                    NavigationStack { NutritionTabView(seeded: model) }
                        .sheet(isPresented: .constant(true)) { MacroEditSheet(model: model) }
                default:
                    NavigationStack { NutritionTabView(seeded: model) }
                }
            } else if NutritionPreviews.model(screen) == nil {
                ContentUnavailableView("No Nutrition screen named \(screen)", systemImage: "questionmark.square.dashed")
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .task {
            if model == nil { model = NutritionPreviews.model(screen) }
            // `NutrientsView` is a PUSHED screen and does not observe; in the
            // app its parent tab holds the streams open behind it.
            if screen == "nutrients" { await model?.observe() }
        }
    }
}

#Preview("Nutrition — under") {
    NutritionPreviews.view("fuel")
}

#Preview("Nutrition — over") {
    NutritionPreviews.view("fuel-over")
}

#Preview("Nutrition — empty") {
    NutritionPreviews.view("fuel-empty")
}
#endif
