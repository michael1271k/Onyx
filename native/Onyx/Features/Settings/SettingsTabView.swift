import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

/// The Settings tab — six `Section`s of a stock `Form` (§5.8).
///
/// ── WHAT THE WEB VERSION DID THAT THIS DOES NOT ─────────────────────────────
/// Four things, all of them WEB-SIM:
///
///   · a `Zone` component drawing its own bordered card per group — a `Section`
///     is that, with correct grouped-list metrics and header semantics;
///   · a units/week-start/motion trio mirrored into six `localStorage` keys and
///     a hand-rolled `window` event bus, because `activeProgram()` is read
///     synchronously during the next React render. The native app reads GRDB,
///     which is reactive, so the mirrors are simply deleted;
///   · a whole-row upsert on every toggle, so flipping Reduce Motion rewrote the
///     calorie target;
///   · a sixteen-field volume editor inline on the hub, with uncontrolled inputs
///     remounted by `key` to reset them. It is a screen of its own here.
///
/// ── AND WHAT WAVE 2.11 CHANGED ──────────────────────────────────────────────
/// Pathfinder is gone — its week-by-week table was a second, worse History, and
/// History is now a door from Today. In its place the tab grew the thing it
/// never had: a Sync section that says, per table, what this device actually
/// holds and when it last heard from the server. A sync you cannot inspect is a
/// sync you have to trust, and §2.3 is a list of the times that was misplaced.
struct SettingsTabView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Supplied only by the screenshot harness, which needs a store it seeded
    /// rather than the signed-in user's. The app never passes one.
    var seeded: SettingsModel?

    @State private var resolved: SettingsModel?

    var body: some View {
        Group {
            if let resolved {
                SettingsForm(model: resolved)
            } else {
                // One frame at most: the model needs the signed-in user id, and
                // that is known by the time this appears.
                ProgressView().controlSize(.large)
            }
        }
        .task {
            if resolved == nil {
                resolved = seeded
                    ?? SettingsModel(database: environment.database, userId: environment.userIdString)
            }
            await resolved?.observe()
        }
    }
}

private struct SettingsForm: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    let model: SettingsModel

    /// Mirrors `ExerciseCardView`'s key — a per-device view preference, not an
    /// account row. Bound with `$` rather than a computed `Binding` because it
    /// has no GRDB row to proxy.
    @AppStorage("onyx.warmupCalculator") private var warmupCalculator = false

    @State private var isSigningOut = false
    @State private var isDeleting = false
    /// Held while the RPC is in flight, so the row cannot be tapped twice.
    @State private var isDeletingNow = false
    /// Non-nil only when the delete FAILED — the account still exists and the
    /// user still has a session, which is the recoverable state.
    @State private var deleteError: String?

    var body: some View {
        Form {
            if let failure = model.failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.onyx.danger)
                        .font(.footnote)
                        .accessibilityAddTraits(.isStaticText)
                }
            }

            Section {
                NavigationLink {
                    PlanView(model: model)
                } label: {
                    LabeledContent("Training plan", value: "\(model.plan.label) · \(model.phase.label)")
                }
                // ── THE ROUTINE BUILDER (W5) ────────────────────────────────
                // Beside the plan, because a routine IS the plan's deck — the
                // `routines` rows `PlanView` already lists read-only. That
                // screen shows what the deck is; this one writes it.
                NavigationLink {
                    RoutineBuilderView(model: RoutinesModel(
                        database: environment.database,
                        userId: userId,
                        programId: model.planId,
                        programLabel: model.plan.label
                    ))
                } label: {
                    LabeledContent("Routines", value: routineSummary)
                }
                NavigationLink {
                    ExerciseImportView(database: environment.database, userId: userId)
                } label: {
                    Text("Import exercises")
                }
            } header: {
                OnyxSectionHeader("Plan", .train)
            }

            Section {
                NavigationLink {
                    LeversView(model: model)
                } label: {
                    LabeledContent("Levers", value: leverSummary)
                }
                NavigationLink {
                    VolumeTargetsView(model: model)
                } label: {
                    LabeledContent("Weekly set volume", value: "\(model.volumeTotal) sets")
                }
                NavigationLink {
                    BodyTargetsView(model: model)
                } label: {
                    LabeledContent(
                        "Body targets",
                        value: model.targetWeightKg.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) kg" } ?? "—"
                    )
                }
                NavigationLink {
                    ReportsListView()
                } label: {
                    LabeledContent("Reports", value: "Weekly")
                }
            } header: {
                OnyxSectionHeader("Targets", .fuel)
            }

            Section {
                Picker("Weight units", selection: unitSystem) {
                    Text("Kilograms").tag("kg")
                    Text("Pounds").tag("lb")
                }
                Picker("Week starts on", selection: weekStartDay) {
                    Text("Sunday").tag(0)
                    Text("Monday").tag(1)
                }
                Toggle("Reduce motion", isOn: reduceMotion)
            } header: {
                OnyxSectionHeader("Units & display", .recover)
            } footer: {
                // Says what each DOES, not what it ought to. Week start is now
                // load-bearing — one `WeekWindow` cuts History, the Workout
                // tab's This-week panel and the weekly export, so changing it
                // re-labels every week in the app. Reduce motion is still only
                // stored: nothing in `Onyx` reads it, and neither does
                // anything read the system setting, so claiming otherwise here
                // would be a lie in a settings footer.
                Text("A week runs \(weekSpanLabel) — History, this week's panel and the weekly export are all cut on it. Reduce motion is stored with your account and honoured by the web app; the native app does not read it yet.")
            }

            Section {
                // A door and not the controls themselves: applying a theme
                // re-ids the app root, which would throw the user out of this
                // screen mid-tap. `AppearanceView` says why in full.
                NavigationLink {
                    AppearanceView()
                } label: {
                    LabeledContent("Appearance", value: themeName)
                }
            } header: {
                OnyxSectionHeader("Appearance", .train)
            } footer: {
                Text("Two colours, and the palette the rest of the app is derived from them. Presets, or pick your own.")
            }

            Section {
                Toggle("Track effort (RPE)", isOn: trackRpe)
                Toggle("Warm-up calculator", isOn: $warmupCalculator)
            } header: {
                OnyxSectionHeader("Training", .train)
            } footer: {
                Text("Adds an RPE control to every logged set. Half of the double-progression rule reads it. The warm-up calculator adds a row of ramp-up loads to each card that can resolve a working weight.")
            }

            // ── THE MANUAL CASCADE (W2, decision 11) ────────────────────────
            // Past edits within 120 days rescore themselves at the door. An
            // older one leaves a mark, and this is the one button that
            // rewrites the whole stored history from it.
            Section {
                Button {
                    environment.recomputeHistory()
                } label: {
                    LabeledContent("Recompute history") {
                        if environment.isRescoring {
                            ProgressView()
                        } else if environment.historyStale {
                            Text("Needed")
                                .onyxType(.caption)
                                .foregroundStyle(Color.onyx.danger)
                        }
                    }
                }
                .disabled(environment.isRescoring)
                .accessibilityLabel("Recompute history")
                .accessibilityHint(environment.historyStale ? "An edit older than 120 days is waiting" : "Rewrites every stored daily score")
            } header: {
                OnyxSectionHeader("History", .body)
            } footer: {
                if let from = environment.historyStaleFrom {
                    Text("Something dated \(from) changed. Edits that old are not rescored automatically; this rewrites every score from there to today.")
                } else {
                    Text("Edits within the last 120 days rescore themselves. This rewrites every stored day from the oldest score to today.")
                }
            }

            // ── ADMIN ONLY, AND FAILING CLOSED ──────────────────────────────
            // The Sync doctor is a diagnostic: per-table row counts, cursors,
            // the outbox backlog. It is the right screen for whoever maintains
            // this and it is a wall of jargon to everyone else, and open
            // sign-up means everyone else is now a real audience.
            //
            // `isAdmin` is false until `profiles.role` has synced, so a fresh
            // account never sees it and the admin sees it a moment late. That
            // asymmetry is deliberate — see `AppEnvironment.role`. Nothing
            // security-relevant hangs on it: RLS does not consult this, and
            // hiding a read-only diagnostic is a tidiness decision, not a
            // permission boundary.
            if environment.isAdmin {
                Section {
                    NavigationLink {
                        SyncStatusView()
                    } label: {
                        LabeledContent("Sync doctor", value: environment.sync.caption(at: .now) ?? "Never synced")
                    }
                } header: {
                    OnyxSectionHeader("Sync", .body)
                } footer: {
                    Text("What this device holds against what the server holds, table by table, and anything still waiting to get there.")
                }
            }

            Section {
                LabeledContent("App", value: "Onyx")
                LabeledContent("Version", value: OnyxLinks.versionString)
                // Support sits ABOVE the policy: it is the row a person in
                // trouble is looking for, and the policy is the one a reviewer
                // is. Both are `Link`, which opens Safari rather than an
                // in-app browser — an app that renders arbitrary web content
                // answers a different set of App Review questions, and neither
                // of these pages is worth that.
                Link("Support", destination: OnyxLinks.support)
                    .accessibilityHint("Opens in Safari")
                Link("Privacy Policy", destination: OnyxLinks.privacyPolicy)
                    .accessibilityHint("Opens in Safari")
            } header: {
                OnyxSectionHeader("About", .recover)
            } footer: {
                // The medical sentence is FIRST because it is the one App Review
                // looks for (guideline 1.4.1). Onyx reads HRV, resting heart
                // rate, SpO₂ and respiratory rate out of HealthKit and tells
                // you what it thinks they mean — "an early fatigue or
                // under-recovery signal" — which is interpretation, and
                // interpretation without this line is what the guideline is
                // about. It measures nothing itself; that is the half of 1.4.1
                // that would be a hard reject.
                Text("Onyx is a training and recovery log, not a medical device. It does not diagnose, treat or monitor any condition — talk to a doctor before making a health decision.\n\nHealth data stays on this device and in your own private Onyx account. It is never sold, and never shared with anyone else.")
            }

            Section {
                Button("Sign out", role: .destructive) { isSigningOut = true }
                // App Store guideline 5.1.1(v): an account that can be created
                // in the app has to be deletable in the app — not by email, not
                // through a web form, here.
                Button("Delete account", role: .destructive) { isDeleting = true }
                    .disabled(isDeletingNow)
            } footer: {
                Text("Deleting your account removes every workout, night and reading from Onyx's servers and from this device. It cannot be undone.")
            }
        }
        .onyxFormBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshToday() }
        }
        .onChange(of: environment.today) { _, _ in model.refreshToday() }
        .confirmationDialog("Sign out of Onyx?", isPresented: $isSigningOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task { await environment.signOut() }
            }
        } message: {
            Text("Anything not yet synced is pushed first, then this device's copy of your data is cleared. Your account and everything on the server are untouched.")
        }
        // Two taps, and the second one spells out the word "delete" in its own
        // label rather than saying "Continue". A destructive action a user can
        // reach by muscle memory is one they will reach by accident.
        .confirmationDialog(
            "Delete your Onyx account?", isPresented: $isDeleting, titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) {
                isDeletingNow = true
                deleteError = nil
                Task {
                    do {
                        // The RPC wipes the server; `deleteAccount` then signs
                        // out, which revokes the session and erases this device.
                        try await environment.deleteAccount()
                    } catch {
                        // Deliberately NOT signed out: an account that still
                        // exists and a phone with no session is a state with no
                        // way to retry. The user stays where they are, told why.
                        deleteError = (error as? LocalizedError)?.errorDescription
                            ?? error.localizedDescription
                    }
                    isDeletingNow = false
                }
            }
        } message: {
            Text("This permanently deletes your account and every workout, night, meal and measurement in it, on every device. It cannot be undone.")
        }
        .alert("Could not delete the account",
               isPresented: .init(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    /// The signed-in user, for the screens that write rows of their own.
    ///
    /// `SettingsModel` holds it privately and every other row on this screen
    /// goes through the model; the routine builder and the importer own their
    /// own writes, so they are handed the id directly. An unresolved auth state
    /// cannot reach this screen — `RootView` shows `SignInView` for it.
    private var userId: String {
        if case let .signedIn(id) = environment.auth { return OnyxJSON.canonicalUserID(id) }
        return ""
    }

    /// The preset the live theme matches, or `Custom`.
    ///
    /// Derived rather than stored: the spec IS the theme, and a name kept
    /// beside it would be a second fact to keep true across a hand-edited
    /// defaults blob. Presets are written as their normalised hexes, so a
    /// stored spec compares equal to the preset it came from.
    ///
    /// `base` and not `spec`: from W2 the drawn palette carries the training
    /// block's mood offset on top of the pick, and no offset spec is in the
    /// table — matching on `spec` would read "Custom" for the whole of a cut.
    private var themeName: String {
        let spec = OnyxTheme.current.base
        return OnyxTheme.presets.first { $0.spec == spec }?.name ?? "Custom"
    }

    /// `5 days · 37 movements`, or the empty state a blank plan starts in.
    private var routineSummary: String {
        let days = model.deck(for: model.planId)?.days ?? []
        guard !days.isEmpty else { return "None yet" }
        let movements = days.reduce(0) { $0 + $1.exercises.count }
        return "\(days.count) \(days.count == 1 ? "day" : "days") · \(movements) movements"
    }

    /// `Baseline · 1,955 kcal`, or the release and the date it ends.
    private var leverSummary: String {
        let kcal = model.shownGoals.calorie.formatted(.number.precision(.fractionLength(0)))
        guard let held = model.heldBy else { return "My own numbers · \(kcal) kcal" }
        return "\(held.label) · \(kcal) kcal"
    }

    /// `Monday to Sunday` — the setting read back as the span it produces,
    /// which is the thing being chosen. "Week starts on: Monday" leaves the
    /// reader to work out which Sunday a session then belongs to.
    private var weekSpanLabel: String {
        let window = WeekWindow(containing: model.today, goals: model.goals)
        let names = Calendar.current.weekdaySymbols
        return "\(names[window.startDay]) to \(names[(window.startDay + 6) % 7])"
    }

    // ── Bindings ────────────────────────────────────────────────────────────
    // Written as computed bindings rather than `@State` mirrors of the row: a
    // mirror has to be kept in step with the stream, and the moment it drifts
    // the control shows one thing while the database holds another. The control
    // reads the store and writes the store, so it cannot disagree with it.

    private var unitSystem: Binding<String> {
        Binding(get: { model.goals?.unitSystem ?? "kg" }, set: { model.setUnitSystem($0) })
    }

    private var weekStartDay: Binding<Int> {
        Binding(
            get: { WeekWindow.startDay(from: model.goals) },
            set: { model.setWeekStartDay($0) }
        )
    }

    private var reduceMotion: Binding<Bool> {
        Binding(get: { model.goals?.reduceMotion ?? false }, set: { model.setReduceMotion($0) })
    }

    private var trackRpe: Binding<Bool> {
        Binding(get: { model.goals?.trackRpe ?? true }, set: { model.setTrackRpe($0) })
    }
}

#if DEBUG
#Preview("Settings") {
    NavigationStack { SettingsTabView() }
        .environment(AppEnvironment.preview)
}
#endif

// ── App Store surfaces ──────────────────────────────────────────────────────
// App Review requires a reachable privacy-policy URL for any app carrying the
// HealthKit entitlement (5.1.1(i)) and a reachable support URL for every app
// (1.5). The SAME two urls go in the App Store Connect metadata fields — see
// `docs/APP_STORE.md` §2 — so they are stated once, here, and read from here.
//
// Both pages are static HTML under `site/` at the repo root, published by
// Netlify with no build step and no login in front of them — a policy page
// behind a login is the rejection it exists to prevent. Moving the app to its
// own domain is a change to `host` alone.
enum OnyxLinks {
    /// The one place the domain is written down. A move is one line, and it
    /// cannot leave the two urls below pointing at different hosts.
    private static let host = "https://onyx-health-fitness.netlify.app"

    static let privacyPolicy = URL(string: "\(host)/privacy/")!
    static let support = URL(string: "\(host)/support/")!

    /// `1.3.0 (10300)` — what a review note or a bug report needs to identify a build.
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
