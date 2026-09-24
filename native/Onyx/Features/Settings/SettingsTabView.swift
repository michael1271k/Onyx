import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

/// The Settings tab — a stock `Form`, one `Section` per thing a control changes
/// (§5.8; regrouped, and every row given a sub-line, in App Store W7).
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
    /// `OnyxReminders.enabledKey` — spelled once, there, and read here through
    /// the same string so the toggle and the scheduler cannot drift.
    @AppStorage(OnyxReminders.enabledKey) private var remindersEnabled = false
    @AppStorage(OnyxReminders.supplementsKey) private var supplementRemindersEnabled = false

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

            // ── EVERY ROW SAYS WHAT IT DOES (App Store W7) ──────────────────
            // A row is a title and one compact sub-line: a label of two `Text`s,
            // which `Form` draws as title and subtitle for a `LabeledContent`, a
            // `Toggle` and a `Picker` alike. That is the eleven
            // `LabeledContent`-in-a-`NavigationLink` rows this screen already
            // had, extended to every row — not a second row type.
            //
            // Footers keep only what a sub-line cannot carry: the medical
            // disclaimer (1.4.1) and what deleting the account destroys.
            //
            // Sections group by what a control CHANGES: the plan and the volume
            // it prescribes; the fuel targets; how a set is logged; what the
            // phone asks you about; how numbers and weeks read; the history
            // those weeks make. Weekly volume sat with the calorie levers and
            // Reports with the targets, and the supplement reminder was a
            // "Training" switch.
            Section {
                NavigationLink {
                    PlanView(model: model)
                } label: {
                    row("Training plan", "Your block and phase", value: "\(model.plan.label)\u{00A0}· \(model.phase.label)")
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
                    row("Routines", "What each day holds", value: routineSummary)
                }
                NavigationLink {
                    VolumeTargetsView(model: model)
                } label: {
                    row("Weekly set volume", "Target sets for each muscle", value: "\(model.volumeTotal) in all")
                }
                NavigationLink {
                    ExerciseImportView(database: environment.database, userId: userId)
                } label: {
                    row("Import exercises", "Add a movement list")
                }
                NavigationLink {
                    LeversView(model: model)
                } label: {
                    row("Levers", model.heldBy.map { "Held by \($0.label)" } ?? "Your own numbers", value: leverSummary)
                }
                NavigationLink {
                    BodyTargetsView(model: model)
                } label: {
                    row(
                        "Body targets", "Weight and muscle goals",
                        value: model.targetWeightKg.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) kg" } ?? "—"
                    )
                }
                NavigationLink {
                    PrescriptionsView(database: environment.database, userId: environment.userIdString)
                } label: {
                    row("Prescriptions", "Paste a coach's audit")
                }
            } header: {
                OnyxSectionHeader("Plan & targets", .train)
            }
            .settingsRows()

            Section {
                Toggle(isOn: trackRpe) {
                    Text("Track effort (RPE)").font(.subheadline)
                    subLine("Progression reads it")
                }
                Toggle(isOn: $warmupCalculator) {
                    Text("Warm-up calculator").font(.subheadline)
                    subLine("Ramp-up loads per card")
                }
                /* ── THE TWO FIGURES NOTHING ELSE COLLECTS ──────────────────
                   Every other number arrives on its own: the watch files the
                   steps, the scale the weight, the logger the sets. A fatigue
                   rating is a person answering a question about themselves and
                   the waist is a person fetching a tape, and the weekly audit
                   keeps finding the same two gaps. Off until asked, because an
                   app that requests notification permission at launch gets
                   "Don't Allow" and can never ask again. */
                Toggle(isOn: $remindersEnabled) {
                    Text("Log reminders").font(.subheadline)
                    subLine("Fatigue and waist check-ins")
                }
                .onChange(of: remindersEnabled) { _, on in
                    armReminders(on) { remindersEnabled = false }
                }
                /* ── THE STACK, AT EACH SLOT'S TIME (App Store W5) ──────────
                   One switch for every supplement reminder. Each names what is
                   still due at that time, at the dose in force that day, and a
                   dose already ticked is not asked about. */
                Toggle(isOn: $supplementRemindersEnabled) {
                    Text("Supplement reminders").font(.subheadline)
                    subLine("At each stack time")
                }
                .onChange(of: supplementRemindersEnabled) { _, on in
                    armReminders(on) { supplementRemindersEnabled = false }
                }
            } header: {
                OnyxSectionHeader("Logging & reminders", .train)
            }
            .settingsRows()

            Section {
                Picker(selection: unitSystem) {
                    Text("Kilograms").tag("kg")
                    Text("Pounds").tag("lb")
                } label: {
                    Text("Weight units").font(.subheadline)
                    subLine("How loads are shown")
                }
                // Week start is load-bearing — one `WeekWindow` cuts History,
                // the Workout tab's This-week panel and the weekly export, so
                // the sub-line says what the choice cuts (the picker already
                // shows the day; a "Sunday–Saturday" line only repeated it).
                Picker(selection: weekStartDay) {
                    Text("Sunday").tag(0)
                    Text("Monday").tag(1)
                } label: {
                    Text("Week starts on").font(.subheadline)
                    subLine("Cuts History and the weekly export")
                }
                // ── AND WHY THERE IS NO "REDUCE MOTION" ROW (W1) ─────────────
                // There was one. It wrote a value nothing read, and the app
                // already honours the SYSTEM setting (`accessibilityReduceMotion`
                // in eight places). A second app-level copy of a system switch
                // is a second answer to one question.
                //
                // Appearance is a door and not the controls themselves: applying
                // a theme re-ids the app root, which would throw the user out of
                // this screen mid-tap. `AppearanceView` says why in full.
                NavigationLink {
                    AppearanceView()
                } label: {
                    row("Appearance", "Theme colours for the whole app", value: themeName)
                }
                // ── THE MANUAL CASCADE (W2, decision 11) ────────────────────────
                // Past edits within 120 days rescore themselves at the door. An
                // older one leaves a mark, and this is the one button that
                // rewrites the whole stored history from it.
                NavigationLink {
                    ReportsListView()
                } label: {
                    row("Reports", "A write-up per week")
                }
                Button {
                    environment.recomputeHistory()
                } label: {
                    LabeledContent {
                        if environment.isRescoring {
                            ProgressView()
                        } else if environment.historyStale {
                            Text("Needed")
                                .onyxType(.caption)
                                .foregroundStyle(Color.onyx.danger)
                        }
                    } label: {
                        Text("Recompute history").font(.subheadline)
                        if let from = environment.historyStaleFrom {
                            subLine("An edit from \(from) waits")
                        } else {
                            subLine("Rewrites stored scores")
                        }
                    }
                }
                .disabled(environment.isRescoring)
                .accessibilityLabel("Recompute history")
                .accessibilityHint(environment.historyStale ? "An edit older than 120 days is waiting" : "Rewrites every stored daily score")
            } header: {
                OnyxSectionHeader("Display & history", .recover)
            }
            .settingsRows()

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
                        row(
                            "Sync doctor", "Phone against server",
                            value: environment.sync.caption(at: .now) ?? "Never synced"
                        )
                    }
                } header: {
                    OnyxSectionHeader("Sync", .body)
                }
            }

            // About and the account are ONE section (overhaul Q20): two
            // groups of three rows each paid a header, a footer and 16 pt of
            // gap for what reads as one closing block.
            Section {
                row("Version", "Quote in a bug report", value: OnyxLinks.versionString)
                    .textSelection(.enabled)
                Link(destination: OnyxLinks.support) {
                    row("Support", "Questions and bugs")
                }
                .accessibilityHint("Opens in Safari")
                Link(destination: OnyxLinks.privacyPolicy) {
                    row("Privacy Policy", "What is kept, never sold")
                }
                .accessibilityHint("Opens in Safari")
                Button("Sign out", role: .destructive) { isSigningOut = true }
                Button("Delete account", role: .destructive) { isDeleting = true }
                    .disabled(isDeletingNow)
            } header: {
                OnyxSectionHeader("About & account", .recover)
            } footer: {
                Text("Onyx is a training and recovery log, not a medical device: it does not diagnose, treat or monitor any condition — talk to a doctor before a health decision. Your data stays on this device and in your private account, never sold or shared. Deleting the account erases it everywhere and cannot be undone.")
            }
            .settingsRows()
        }
        .onyxFormBackground()
        .settingsDensity()
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

    /// Both reminder switches. Turning one ON is the one moment permission is
    /// asked — never at launch, where it gets "Don't Allow" and can never be
    /// asked again. Refused at the system sheet, the switch goes back rather
    /// than sitting on beside nothing; either way the week is re-armed, so
    /// turning one OFF clears exactly its own.
    private func armReminders(_ on: Bool, refused: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            if on, await !OnyxReminders.requestAuthorization() {
                refused()
                return
            }
            OnyxReminders.refresh(database: environment.database, userId: environment.userIdString)
        }
    }

    /// A title, its one-line sub-line, and the current value if it has one.
    /// `Form` styles the label's second `Text` as the subtitle.
    ///
    /// The value is primary ink, not the platform's grey: when it does not fit
    /// beside a sub-line it drops UNDER it (every value row at AX5, two at the
    /// default size), and grey-under-grey read as one paragraph.
    private func row(_ title: String, _ detail: String, value: String? = nil) -> some View {
        LabeledContent {
            if let value {
                Text(value)
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(Color.onyx.textPrimary)
                    // One line: a value that wrapped under its label (Levers)
                    // cost the row a third line.
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        } label: {
            Text(title).font(.subheadline)
            subLine(detail)
        }
    }

    /// Grey even inside a `Link` or `Button`, whose tint would otherwise dim it
    /// to an accent-on-grey that reads as a second link and fails contrast.
    private func subLine(_ text: String) -> Text {
        Text(text).font(.footnote).foregroundStyle(Color.onyx.textSecondary)
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
        return "\(days.count) \(days.count == 1 ? "day" : "days")\u{00A0}· \(movements) movements"
    }

    /// `Baseline · 1,955 kcal`, or the release and the date it ends.
    /// The kcal alone: who holds the numbers moved to the detail line, so the
    /// value fits beside its label instead of wrapping onto a third line.
    private var leverSummary: String {
        "\(model.shownGoals.calorie.formatted(.number.precision(.fractionLength(0)))) kcal"
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
