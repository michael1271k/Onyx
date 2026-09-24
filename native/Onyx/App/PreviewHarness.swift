#if DEBUG
import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

/// One screen, seeded, for `scripts/native-shot.sh`.
///
/// ── WHY THE SHOT LOOP NEEDS A DOOR AT ALL ───────────────────────────────────
/// A screenshot of a settings screen is only useful if it shows the same numbers
/// every time. Reaching the real You tab means signing in, which means network,
/// a live database and whatever this week's training happens to look like — so
/// the diff in `native/__screenshots__` would be a diff of the data, not of the
/// design, and would churn on every run.
///
/// This launches straight into one screen backed by an in-memory database that
/// holds exactly what the shot is demonstrating. `#if DEBUG`, and reached only
/// through a launch argument, so it cannot ship and cannot be stumbled into.
enum PreviewHarness {

    /// Two cascades in the ledger, so Sync doctor's Rescores section has rows
    /// to draw (W2). Written into the preview store, read by the view.
    @MainActor static func withRescoreLedger(_ env: AppEnvironment) -> AppEnvironment {
        let userId = env.userIdString
        try? env.database.recordSync(userId: userId, table: "rescore", rows: 49, reason: "session-edit 2026-08-01 → 2026-09-18", at: Date().addingTimeInterval(-3_600))
        try? env.database.recordSync(userId: userId, table: "rescore", rows: 3, reason: "day-edit 2026-09-16 → 2026-09-18", at: Date().addingTimeInterval(-90))
        return env
    }

    /// `--onyx-screen you` on the launch command line.
    static var requestedScreen: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--onyx-screen"),
              index + 1 < arguments.count
        else { return nil }
        return arguments[index + 1]
    }

    /// A store holding one plausible week of settings.
    ///
    /// The figures are the live block's: Lever 1 is not selected, so the screens
    /// show the user's own numbers — the state with the most controls visible,
    /// which is the one worth photographing.
    /// Built once: `view(_:)` is a `@ViewBuilder` and runs on every evaluation,
    /// and a model constructed inside it is a NEW model each time — the
    /// `.task { model.observe() }` then observes an instance the rendered view
    /// no longer holds, which since W2 (the catalogue arrives by observation)
    /// photographed an empty plan and no rungs.
    @MainActor static let sharedSettingsModel: SettingsModel = seededModel()

    @MainActor
    static func seededModel() -> SettingsModel {
        let database = try! AppDatabase.inMemory(deviceId: "shot")
        // The catalogue as rows (W2): decks, plans, phases, rungs.
        PreviewCatalogue.seed(database)
        let userId = "00000000-0000-0000-0000-000000000001"
        _ = try? database.editUserGoals(userId: userId) { row in
            row.calorieGoal = 1955
            row.proteinGoalG = 170
            row.carbsGoalG = 195
            row.fatGoalG = 55
            row.stepsGoal = 10000
            row.activeCalGoal = 500
            row.sleepGoalHours = 8
            row.waterGoalMl = 3000
            row.activeLever = "custom"
            row.activePlan = "onyx5"
            row.activePhase = ProgramPhase.cut.rawValue
            row.unitSystem = "kg"
            row.weekEndDay = 6
            row.trackRpe = true
            row.targetWeightKg = 62
            row.targetBodyFatPct = 13
            row.targetMuscleMassKg = 33
        }
        _ = try? database.editPlanPhaseGoals(userId: userId, planId: "onyx5", phase: "cut") { row in
            row.kcal = 1955
            row.proteinG = 170
            row.carbsG = 195
            row.fatG = 55
            row.stepsGoal = 10000
            row.targetWeightKg = 62
        }
        return SettingsModel(database: database, userId: userId)
    }

    /// A week of real movements, one per display group, so the library shot
    /// exercises every heading and the detail shot lands on a lift with both a
    /// primary and an assisting muscle.
    ///
    /// Six of them carry the ids of the movements the history seed actually holds sets for
    /// (`HistoryPreviews`), so the library shot draws REAL sparklines on those
    /// rows and honest blanks on the rest — which is what the screen looks like
    /// for anyone who has trained a movement once.
    static let sampleExercises: [ExerciseCatalogEntry] = [
        .init(id: "ex-incline", name: "Incline DB Press", setCount: 48, lastTrained: "2026-09-02"),
        .init(id: "2", name: "Pec Deck", setCount: 30, lastTrained: "2026-09-01"),
        .init(id: "ex-pulldown", name: "Lat Pulldown", setCount: 36, lastTrained: "2026-09-02"),
        .init(id: "ex-row", name: "Seated Cable Row (Wide Grip)", setCount: 22, lastTrained: "2026-09-02"),
        .init(id: "5", name: "Shoulder Press", setCount: 27, lastTrained: "2026-09-02"),
        .init(id: "ex-raise", name: "Single Arm Lateral Raise", setCount: 41, lastTrained: "2026-09-02"),
        .init(id: "7", name: "Rope Triceps Pushdown", setCount: 33, lastTrained: "2026-08-30"),
        .init(id: "8", name: "Seated Incline DB Curl", setCount: 26, lastTrained: "2026-08-30"),
        .init(id: "ex-hack", name: "Hack Squat", setCount: 24, lastTrained: "2026-08-30"),
        .init(id: "10", name: "Seated Leg Curl", setCount: 21, lastTrained: "2026-08-29"),
        .init(id: "11", name: "Calf Press", setCount: 30, lastTrained: "2026-08-29"),
        .init(id: "ex-hkr", name: "Hanging Knee Raise", setCount: 18, lastTrained: "2026-09-02"),
    ]

    /// A morning walk and a lunchtime ride, as Health would hand them over.
    ///
    /// One of each shape the card has to survive: a bout with everything
    /// (distance, pace, heart rate, ascent, energy) and one with no ascent,
    /// because an indoor ride records none and the card must not print a dash
    /// for it. Times are absolute so the shot does not move with the clock.
    static let sampleBouts: [WorkoutSample] = {
        let day = LogicalDay.date(fromISO: "2026-09-03") ?? Date()
        let at: (Int, Int) -> Date = { hour, minute in
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        return [
            WorkoutSample(
                start: at(7, 12), end: at(7, 53), isLifting: false,
                cardioKind: CardioImport.walk, distanceM: 4_240, activeKcal: 218,
                avgHr: 112, elevationM: 38
            ),
            WorkoutSample(
                start: at(12, 40), end: at(13, 18), isLifting: false,
                cardioKind: CardioImport.cycling, distanceM: 14_800, activeKcal: 340,
                avgHr: 131, elevationM: nil
            ),
        ]
    }()

    /// The bout ghosted behind the empty state.
    static let sampleLastBout = CardioLogRow(
        id: "preview-bout", userId: "00000000-0000-0000-0000-000000000001", date: "2026-09-01", kind: CardioImport.walk,
        distanceM: 3_980, durationMin: 39, fromHealthkit: true, createdAt: nil,
        activeKcal: 201, avgHr: 108
    )

    static let previewUser = "00000000-0000-0000-0000-000000000001"

    static let dsldHits: [DSLD.Hit] = [
        .init(id: "323076", brand: "Thorne", product: "Basic Nutrients 2/Day", form: "Capsule", serving: "2 Capsule(s)"),
        .init(id: "291772", brand: "Thorne", product: "Basic Nutrients 2/Day", form: "Capsule", serving: nil, offMarket: true),
        .init(id: "28427", brand: "Thorne Research", product: "Basic Nutrients 2/Day", form: "Capsule", serving: nil, offMarket: true),
        .init(id: "253226", brand: "KAL", product: "Magnesium Glycinate 400", form: "Tablet or Pill", serving: nil),
        .init(id: "33919", brand: "Vinco's", product: "Magnesium Glycinate", form: "Powder", serving: nil),
    ]

    static let dsldLabel: DSLD.Label? = {
        func row(_ name: String, _ amount: Double, _ unit: String, _ dv: Double?) -> String {
            #"{"name": "\#(name)", "quantity": [{"quantity": \#(amount), "unit": "\#(unit)", "dailyValueTargetGroup": [{"percent": \#(dv.map { "\($0)" } ?? "null")}]}]}"#
        }
        let rows = [
            row("Vitamin A", 1.05, "mg", 117), row("Vitamin C", 250, "mg", 278), row("Vitamin D", 50, "mcg", 250),
            row("Vitamin E", 16.5, "mg", 110), row("Vitamin K", 400, "mcg", 333), row("Thiamine", 50, "mg", 4167),
            row("Vitamin B6", 20, "mg", 1176), row("Folate", 667, "mcg DFE", 167), row("Vitamin B12", 600, "mcg", 25000),
            row("Magnesium", 20, "mg", 5), row("Zinc", 15, "mg", 136), row("Selenium", 200, "mcg", 364),
            row("Boron", 2, "mg", nil), row("Lutein", 140, "mcg", nil),
        ].joined(separator: ",")
        let json = #"{"id": 323076, "fullName": "Basic Nutrients 2/Day", "brandName": "Thorne", "physicalState": {"langualCodeDescription": "Capsule"}, "servingSizes": [{"minQuantity": 2, "maxQuantity": 2, "unit": "Capsule(s)"}], "ingredientRows": [\#(rows)]}"#
        return try? JSONDecoder().decode(DSLD.Label.self, from: Data(json.utf8))
    }()

    /// A store that already holds one of the names in the seeded paste, so the
    /// preview shot shows a duplicate being recognised rather than only the
    /// happy path.
    @MainActor
    static func importStore() -> AppDatabase {
        let database = try! AppDatabase.inMemory(deviceId: "shot-import-preview")
        _ = try? database.createExercise(userId: previewUser, name: "Lat Pulldown")
        return database
    }

    /// An empty store, run through the real onboarding flow.
    ///
    /// Returns the environment it produced and the day the schedule says to
    /// train — which for a five-day split is a real training day four times out
    /// of seven and a rest day otherwise, so the day is pinned to the first of
    /// the routine rather than left to the calendar. The shot is of a DECK, not
    /// of whether today happens to be a Wednesday.
    @MainActor
    static func newAccount() -> (AppEnvironment, ProgramDay?) {
        let database = try! AppDatabase.inMemory(deviceId: "shot-new-account")
        let model = OnboardingModel(database: database, userId: previewUser)
        model.planId = "onyx5"
        // The flow's own value, written synchronously. `finish()` is async only
        // because a button calls it; `seedValue()` is the same answer and
        // `seedAccount` is one transaction, so the rows are there when this
        // returns.
        _ = try? database.seedAccount(model.seedValue())
        let context = try? database.scheduleContext(userId: previewUser)
        let environment = AppEnvironment(
            database: database,
            supabase: OnyxSupabase.makeClient(
                config: SupabaseConfig(url: URL(string: "https://preview.invalid")!, anonKey: "preview")
            )
        )
        return (environment, context?.activeProgram.days.first)
    }

    /// The routine builder over the seeded catalogue — a real five-day split.
    ///
    /// Built fresh per shot and NOT shared: `RoutineBuilderView` and
    /// `RoutineDayEditor` each `.task { model.load() }`, and a model shared
    /// between two shots would carry the first one's reload into the second.
    @MainActor
    static func routinesModel() -> RoutinesModel {
        let database = try! AppDatabase.inMemory(deviceId: "shot-routines")
        PreviewCatalogue.seed(database)
        // The CATALOGUE too, not only the routines. `PreviewCatalogue` seeds
        // `routines` and nothing else, so the first shot of this screen was a
        // wall of thirty-three "not in your exercise list" — a state this screen
        // now words differently, but not the one worth photographing as normal.
        for day in (try? database.routineDays(userId: previewUser, programId: "onyx5")) ?? [] {
            for exercise in day.payload.exercises {
                _ = try? database.createExercise(userId: previewUser, name: exercise.name)
            }
        }
        let model = RoutinesModel(
            database: database, userId: previewUser, programId: "onyx5", programLabel: "Onyx-5"
        )
        model.load()
        return model
    }

    /// `onboarding-volume` → a model parked on the volume step.
    ///
    /// The bodyweight and goal are the flow's own defaults, so the macros and
    /// the MEV numbers on screen are exactly what a real new account is shown —
    /// a shot that seeded nicer figures would be photographing a screen nobody
    /// gets. The records step carries two filled fields and three blank, which
    /// is the state worth reviewing: the one where a person has answered part
    /// of an optional question.
    @MainActor
    static func onboardingModel(_ screen: String) -> OnboardingModel {
        let model = OnboardingModel(
            database: try! AppDatabase.inMemory(deviceId: "shot-onboarding"),
            userId: "00000000-0000-0000-0000-000000000001"
        )
        let name = screen.replacingOccurrences(of: "onboarding-", with: "")
        let steps: [String: OnboardingModel.Step] = [
            "welcome": .welcome, "you": .you, "goal": .goal, "targets": .targets,
            "volume": .volume, "records": .records, "plan": .plan, "done": .done,
        ]
        model.step = steps[name] ?? .welcome
        if model.step.rawValue >= OnboardingModel.Step.records.rawValue {
            model.oneRepMaxes = ["Bench Press": 92.5, "Squat": 120]
        }
        if model.step.rawValue >= OnboardingModel.Step.plan.rawValue {
            model.planId = PlanTemplates.plans.first?.id
        }
        return model
    }

    /// The theme a shot was asked for, applied before anything draws.
    ///
    /// ── WHY A LAUNCH ARGUMENT AND NOT THE DEFAULTS SUITE ────────────────────
    /// The honest way to theme the app is to write the App Group suite, which
    /// is what Settings does — and doing that from a shot would leave the
    /// simulator's container holding the last theme photographed, so the NEXT
    /// run's "default" shot would come out in whatever colour the previous one
    /// picked. A launch argument dies with the process.
    ///
    /// `--onyx-theme Obsidian` names a preset; `--onyx-theme 6B78F0,E3A650`
    /// gives the two hexes directly, which is how a CUSTOM pair is photographed
    /// without adding it to `OnyxTheme.presets`. Anything unrecognised leaves
    /// the default in place, so a typo photographs the default rather than
    /// failing the run — which is why the name here has to track the table: it
    /// said `Ember` until W3 replaced the presets, and a shot run following
    /// that would have come out in Ion under nine different filenames.
    ///
    /// The hex form takes the two accents only, so it photographs a custom PAIR
    /// at the NEUTRAL mood. A custom chroma/lift is reachable only through a
    /// preset; nothing has needed to photograph one yet.
    @MainActor
    static func applyRequestedTheme() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--onyx-theme"),
              arguments.index(after: flag) < arguments.endIndex
        else { return }
        let value = arguments[arguments.index(after: flag)]
        if let preset = OnyxTheme.presets.first(where: { $0.name.lowercased() == value.lowercased() }) {
            OnyxTheme.set(preset.spec)
            return
        }
        let hexes = value.split(separator: ",").compactMap { UInt32($0, radix: 16) }
        guard hexes.count == 2 else { return }
        OnyxTheme.set(OnyxThemeSpec(primary: hexes[0], secondary: hexes[1]))
    }

    /// The preview environment, opened on the tab the screen name asks for.
    ///
    /// `selectedTab` and not `ONYX_START_TAB`: the launch environment is read
    /// once, by `SignedInTabs.initialTab`, and `simctl launch` passes ARGUMENTS
    /// — which is the same reason `--onyx-screen` is an argument and not a deep
    /// link. An unknown suffix leaves the environment on its default tab rather
    /// than inventing one.
    @MainActor static func tabsEnvironment(_ screen: String) -> AppEnvironment {
        let environment = AppEnvironment.preview
        let tab = screen.hasPrefix("tabs-") ? String(screen.dropFirst("tabs-".count)) : ""
        if ["today", "train", "fuel", "body", "you"].contains(tab) { environment.selectedTab = tab }
        return environment
    }

    /// The harness screen, plus `--onyx-measure` (overhaul C1/C3): four seconds
    /// after launch, print the tallest scroll view's content and visible
    /// heights as `ONYXMEASURE content=… container=…` on stdout. A `List` or
    /// `Form` is a collection view SwiftUI's own scroll geometry cannot read,
    /// and "≤ 1.1 screens" is a claim that needs a number.
    @MainActor
    static func view(_ screen: String) -> some View {
        screenView(screen).task {
            guard ProcessInfo.processInfo.arguments.contains("--onyx-measure") else { return }
            try? await Task.sleep(for: .seconds(4))
            var tallest: UIScrollView?
            func walk(_ view: UIView) {
                if let scroll = view as? UIScrollView,
                   scroll.contentSize.height > (tallest?.contentSize.height ?? 0) { tallest = scroll }
                view.subviews.forEach(walk)
            }
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.flatMap(\.windows).forEach(walk)
            if let s = tallest {
                // A List/Form ESTIMATES the rows it has not laid out, so walk
                // to the bottom until the real height stops moving.
                for _ in 0..<6 {
                    s.setContentOffset(CGPoint(x: 0, y: max(0, s.contentSize.height - s.bounds.height + s.adjustedContentInset.bottom)), animated: false)
                    try? await Task.sleep(for: .milliseconds(300))
                }
                let visible = s.bounds.height - s.adjustedContentInset.top - s.adjustedContentInset.bottom
                print("ONYXMEASURE content=\(s.contentSize.height) container=\(visible)")
            }
        }
    }

    @MainActor @ViewBuilder
    static func screenView(_ screen: String) -> some View {
        let _ = applyRequestedTheme()
        let model = sharedSettingsModel
        switch screen {
        case "signin":
            SignInView().environment(AppEnvironment.preview)
        // ── ONBOARDING, ONE SCREEN PER STEP (W5) ────────────────────────────
        // A fresh model per shot, over an EMPTY in-memory store — which is the
        // state the flow actually runs in, and the one thing the seeded
        // `sharedSettingsModel` above cannot represent. The step is set
        // directly rather than by tapping through, so a shot of step six does
        // not depend on the five before it still working.
        case let s where s.hasPrefix("onboarding"):
            OnboardingFlow(model: onboardingModel(s))
                .environment(AppEnvironment.preview)
        // ── THE ROUTINE BUILDER (W5) ────────────────────────────────────────
        // Over the seeded catalogue, so the list is a real five-day split and
        // the day editor opens on a day with seven movements in it — the state
        // where the per-movement row has to survive its own width.
        case "routines":
            NavigationStack { RoutineBuilderView(model: routinesModel()) }
                .environment(AppEnvironment.preview)
        case "routine-day":
            NavigationStack {
                RoutineDayEditor(model: routinesModel(), dayKey: "cb_a")
            }
            .environment(AppEnvironment.preview)
        // Empty, which is what "Build my own" lands on and the state a builder
        // is judged by: a screen with nothing in it still has to say what to do.
        case "routines-empty":
            NavigationStack {
                RoutineBuilderView(model: RoutinesModel(
                    database: try! AppDatabase.inMemory(deviceId: "shot-routines-empty"),
                    userId: previewUser, programId: "my-plan", programLabel: "My plan"
                ))
            }
            .environment(AppEnvironment.preview)
        // ── W5'S GATE, ON A SIMULATOR ───────────────────────────────────────
        // A brand-new account, set up by the REAL `OnboardingModel.finish()`
        // over an empty store, and then the screens it lands on. Nothing here
        // is a fixture of the finished state: the plan, the deck, the targets
        // and the catalogue are all written by the same code a person's first
        // launch runs, so a shot of these is a shot of the wave's gate.
        //
        // The auth leg is the only part left out — it needs a confirmed e-mail
        // and a network, and it is W4-era code this wave did not touch.
        case "new-account-train", "new-account-logger":
            let (environment, day) = newAccount()
            if screen == "new-account-train" {
                NavigationStack { WorkoutTabView(seededDay: day) }
                    .environment(environment)
                    .preferredColorScheme(.dark)
            } else {
                NavigationStack {
                    LiveLoggerView(model: LoggerModel(
                        day: day ?? PlanTemplates.day("onyx5", "cb_a"), phase: .cut,
                        store: environment.database, userId: previewUser
                    ))
                }
                .environment(environment)
                .preferredColorScheme(.dark)
            }
        case "import-exercises":
            NavigationStack {
                ExerciseImportView(
                    database: try! AppDatabase.inMemory(deviceId: "shot-import"),
                    userId: previewUser
                )
            }
            .environment(AppEnvironment.preview)
        // The preview state, over a store that already holds one of the names —
        // so the shot carries all three verdicts at once: a clean import, a
        // duplicate that will be left alone, and a movement nothing can
        // classify. That third row is the one worth reviewing.
        case "import-preview":
            NavigationStack {
                ExerciseImportView(
                    database: importStore(), userId: previewUser,
                    seededPaste: """
                    Exercise Name,Primary Muscle,Secondary Muscles,Equipment
                    Zercher Squat,Quads,Glutes,Barbell
                    Meadows Row,Lats,Biceps,Barbell
                    Lat Pulldown,Lats,,Cable
                    Jefferson Curl,,,Barbell
                    Copenhagen Plank,,,Bodyweight
                    """
                )
            }
            .environment(AppEnvironment.preview)
        case "backfill":
            BackfillSheet(model: .preview).environment(AppEnvironment.preview)
        // ── THE TAB BAR ITSELF (W8) ─────────────────────────────────────────
        // `tabs-today` … `tabs-you`. Every other screen here is one tab's
        // CONTENT with the shell taken off, so the selected-item tint — the
        // whole of W8.1 — appears in none of them.
        //
        // A `TabView` mounts only the selected tab's content, so this is one
        // screen plus five icons, not five screens. Pair it with `SHOT_THEME`:
        // the point of the shot is that the icon moves when the palette does.
        case let s where s.hasPrefix("tabs"):
            SignedInTabs().environment(tabsEnvironment(s))
        case "you":
            NavigationStack { SettingsTabView(seeded: model) }.environment(AppEnvironment.preview)
        // ── OVERHAUL C3: the label-database import, with NO network ─────────
        // Results as a product search for "basic nutrients" answered, and the
        // label itself (an excerpt of DSLD 323076, Thorne "Basic Nutrients
        // 2/Day" — the full response is OnyxCore's decoder fixture).
        case "stack-import", "stack-import-label":
            DSLDImportView(
                onAdd: { _ in }, onManual: { _ in },
                seed: .init(query: "basic nutrients", hits: Self.dsldHits,
                            label: screen == "stack-import-label" ? Self.dsldLabel : nil)
            )
            .environment(AppEnvironment.preview)
            .preferredColorScheme(.dark)
        case "train", "train-done", "train-pending", "train-cardio", "train-empty", "train-week", "train-wrap", "train-wrap-large",
             "train-wrap-deload", "train-report-large", "train-monday", "train-library", "train-library-open",
             // W4: the weekly report the wrap sheet became, seeded — the one
             // shot that can show its lower four blocks whatever the store says.
             "train-report",
             "train-customize", "train-customized", "share-card":
            // Seeded from the history store: the This-week panel and the
            // Ready-to-progress box are both reads over the ledger, so an empty
            // database photographs the empty states rather than the screen.
            HistoryPreviews.view(screen)
        // ── APPEARANCE, AND THE LOCK ────────────────────────────────────────
        // The locked variant is the seam this screen exists to respect: a theme
        // write re-ids the app root and would take a live `LoggerModel` with
        // it. The flag is published directly rather than by starting a session,
        // because the shot is of the REFUSAL, not of the workout.
        case "appearance", "appearance-locked":
            NavigationStack { AppearanceView() }
                .environment(AppEnvironment.preview)
                // In `.task` and not inline: `AppEnvironment.preview` is a
                // shared observable, and writing it while the ViewBuilder runs
                // is a mutation during a view update — of the one property the
                // screen below reads.
                .task { AppEnvironment.preview.publishSessionLive(screen.hasSuffix("locked")) }
        case "sync-status":
            NavigationStack { SyncStatusView(seeded: .preview) }.environment(AppEnvironment.preview)
        // The same screen with every fault it can name — a table behind the
        // server, one ahead, one that could not be counted, two split across
        // user ids, and a rejected write. `sync-status` is the quiet twin, and
        // the pair is the review: a tint means nothing without the state it is
        // a departure from.
        case "sync-doctor":
            NavigationStack { SyncStatusView(seeded: .faults) }.environment(Self.withRescoreLedger(AppEnvironment.preview))
        case "levers":
            NavigationStack { LeversView(model: model) }
        case "plan":
            NavigationStack { PlanView(model: model) }
        case "body":
            NavigationStack { BodyTargetsView(model: model) }
        case "volume":
            NavigationStack { VolumeTargetsView(model: model) }
        case "library":
            HistoryPreviews.view("library")
        case "exercise":
            NavigationStack {
                ExerciseDetailView(entry: sampleExercises[3], siblings: sampleExercises)
            }
            .environment(HistoryPreviews.environment())
        case "reports":
            NavigationStack { ReportsListView(seeded: PreviewReport.rows) }
                .environment(AppEnvironment.preview)
        case "report":
            NavigationStack {
                ReportReaderView(report: PreviewReport.rows[0], seededBody: PreviewReport.body)
            }
            .environment(AppEnvironment.preview)
        // The paste target. Seeded on a week with NOTHING on it, because the
        // placeholder is the half of this screen that had never been drawn.
        case "report-edit":
            ReportEditorSheet(
                week: ReportWeek(start: "2026-08-30", end: "2026-09-05", report: nil, isCurrent: true),
                seededBody: nil
            )
            .environment(AppEnvironment.preview)
        // W7: the same screen with a report that CARRIES an `onyx-targets`
        // block. The bar under the editor is the only thing that tells a
        // reader the paste held targets, so it is the thing to photograph.
        case "report-edit-targets":
            ReportEditorSheet(
                week: ReportWeek(start: "2026-09-13", end: "2026-09-19",
                                 report: PreviewReport.rows[0], isCurrent: false),
                seededBody: PreviewReport.bodyWithTargets
            )
            .environment(AppEnvironment.preview)
        // W7: the diff a paste opens before anything is written. The plan is a
        // VALUE here rather than a store read — `targetsPlan` needs a goals row
        // and the harness has none, and a sheet photographed against an empty
        // store would show every line as "not set → 2,100 kcal", which is the
        // one state this screen exists to avoid drawing.
        case "apply-targets":
            ApplyTargetsSheet(plan: PreviewReport.plan)
                .environment(AppEnvironment.preview)
        case "day", "day-rows", "day-past", "day-session", "day-two", "day-empty", "day-stress", "day-edit", "day-soreness", "day-hero",
             "scale", "scale-first", "day-swap", "doms", "doms-rate",
             "pulse-squares", "pulse-squares-evening", "pulse-squares-empty", "stack", "stack-before", "stack-add", "stack-edit",
             "sleep-edit", "stress", "fatigue", "stress-log", "stress-day", "quick-log",
             // W6: the three day answers merged onto one sheet.
             "log-day", "log-day-soreness", "log-day-water":
            PulsePreviews.view(screen)
        case "fuel", "fuel-over", "fuel-empty", "nutrients", "macro-edit", "fuel-calendar":
            NutritionPreviews.view(screen)
        // The minimised session. See `MiniPlayerHarness` for why it is not
        // photographed on `train`.
        case "mini-player":
            MiniPlayerHarness().environment(AppEnvironment.preview)
        // W4 (App Store): the paired-simulator sync test's phone half.
        case "watch-sync":
            WatchSyncHarness()
        case "logger", "logger-stats", "logger-lifts", "logger-paused", "logger-finish", "logger-options", "logger-timer",
             // W10: the rest bar and the progression cue, on one card.
             "logger-rest", "logger-effort",
             "set-row", "set-row-split", "set-row-cardio", "set-row-records", "set-options", "effort-picker",
             // W5: the heart-rate chart (seeded Health) and the Hevy card (fixture).
             "telemetry-finish", "telemetry-detail", "hevy-card",
             // Overhaul C1: the inline HR strip over a seeded cache row.
             "session-hr",
             // Overhaul W5: the replay's share files, with heart rate.
             "session-share",
             // W3: the mid-session add.
             "logger-add":
            LoggerPreviews.view(screen)
        // ── THE CARDIO SHEET, IN BOTH OF ITS STATES ────────────────────────
        // It had never had a shot, which is most of how it got to look the way
        // it did. It has two now because the screen has two: what it draws when
        // Health has bouts to offer, and what it draws when it has none. The
        // second is the one that used to be four hundred points of black.
        //
        // The bouts are SEEDED rather than read. A HealthKit query on a
        // simulator returns nothing, every time, so a shot of the live read
        // would photograph the empty state twice and call one of them "import".
        case "cardio":
            CardioLogSheet(
                userId: "preview", date: "2026-09-03", onSave: { _ in true },
                bouts: { PreviewHarness.sampleBouts }
            )
            .environment(AppEnvironment.preview)
        case "cardio-empty":
            CardioLogSheet(
                userId: "preview", date: "2026-09-03", onSave: { _ in true },
                bouts: { [] }, lastBout: PreviewHarness.sampleLastBout
            )
            .environment(AppEnvironment.preview)
        case "today", "today-edit", "today-sheet", "today-sheet-vitals",
             "today-sheet-steps", "today-sheet-muscle", "today-sheet-records",
             "today-weighin", "today-board",
             // W7: the Mega Widget, a connected stack, and the jiggle as a
             // reader who has turned motion off sees it.
             "today-mega", "today-stack-linked", "today-edit-still",
             // W6: the relevance order, at 07:00 and at 20:00.
             "today-morning", "today-evening":
            TodayPreviews.view(screen)
        case "history", "history-week", "history-week-live", "history-week-wrapped",
             "history-week-wrap-open", "session", "session-ledger", "exercise-history",
             // Overhaul W5: the share files with no heart rate (tonnage bar).
             "session-share-bars",
             // W2 (refinement): the ledger header's row 2, swapped.
             "session-ledger-assists",
             "session-atlas", "session-edit", "logger-edit", "session-records",
             // W10: the two seconds a record row opens on.
             "session-margin",
             // W4: the pair table, and a day that is only a bout.
             // W1 (refinement): the same table with its agreeing pairs merged.
             "session-pairs", "session-pairs-merged", "session-cardio":
            HistoryPreviews.view(screen)
        case "trends", "trends-empty", "trends-maintenance":
            TrendsPreviews.view(screen)
        case "body-trends", "body-trends-empty", "body-trends-tooltip", "body-trends-stress":
            BodyTrendsPreviews.view(screen)
        case let s where s.hasPrefix("widgets"):
            WidgetPreviews.view(s)
        default:
            // Visible rather than silent: a typo in the shot script should
            // produce a photograph of the mistake, not of the last screen.
            ContentUnavailableView(
                "No harness screen named \(screen)",
                systemImage: "questionmark.square.dashed"
            )
        }
    }
}
/// The phone half of the paired-simulator sync test (App Store W4).
///
/// The REAL Train tab over the preview store, with the one thing a harness
/// never does: the watch link is opened and a context is pushed to the wrist,
/// so the paired watch simulator resolves the same split this tab opens.
/// "Start workout" is then the shipping button, the logger the shipping
/// cover, and the pulse the shipping send — nothing here stands in for them.
///
/// The context goes out under `userIdString`, which is "" here: the logger
/// writes its rows under the same value, and the wrist only rejoins a row
/// whose user matches its context. The schedule is the preview catalogue's,
/// with today pinned to Upper B so the shot does not depend on the weekday.
struct WatchSyncHarness: View {
    private let environment = AppEnvironment.preview

    var body: some View {
        NavigationStack {
            WorkoutTabView(seededDay: PlanTemplates.program("onyx5")?.day(key: "cb_b"))
        }
        .environment(environment)
        .task {
            environment.watchBridge.start()
            // Straight after `start`: a push made before `WCSession` has
            // activated is held and sent on activation (`WatchLink.unsent`).
            let today = LogicalDay.today()
            guard var schedule = try? environment.database.scheduleContext(userId: PreviewCatalogue.userId) else { return }
            schedule.overrides[today] = "cb_b"
            environment.watchBridge.send(userId: environment.userIdString, today: today, schedule: schedule, tiles: nil)
        }
    }
}
#endif
