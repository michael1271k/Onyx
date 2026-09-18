import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

/// One week, day by day (§5.9).
///
/// Seven rows and never fewer. A rest day and a missed day both have nothing in
/// the database to draw from, and they are the two facts a training log is most
/// often consulted for — so the row is built from the SCHEDULE and then filled
/// in from what was logged, rather than built from what was logged and padded.
struct WeekDaysView: View {
    @Environment(AppEnvironment.self) private var environment

    let window: WeekWindow
    /// Supplied only by the screenshot harness.
    var seeded: HistoryWeeks.WeekDetail?

    @State private var detail: HistoryWeeks.WeekDetail?
    /// The generation this screen's data was read at.
    ///
    /// `.task(id:)` fires on appear too, and this screen deliberately reads its
    /// whole ledger once. Keying the guard on the generation preserves that and
    /// re-reads exactly when a rescore cascade has finished rewriting what is
    /// under it — see `AppEnvironment.rescoreGeneration`.
    @State private var loadedAt = -1

    /// The week as a `.md` FILE, written to the temporary directory.
    ///
    /// A `URL` and not a `String`: `ShareLink` hands a string to the sheet as
    /// loose text, so Files offers no "Save to", Mail has nothing to attach and
    /// the artefact reaches the other side with no name. A file arrives as
    /// `onyx-week-07-2026-08-30.md`, which is what makes a weekly document
    /// something you can keep rather than something you can paste once.
    @State private var exportFile: URL?

    /// The week as a `WeeklyWrap.Summary`, when it closed as one (W1b).
    ///
    /// Nil is the honest answer for three different weeks and the chip is
    /// absent for all of them: a week still being lived, a week that missed a
    /// planned day, and a week from a block this plan's layout cannot speak
    /// for. See `WorkoutWeek.wrap(_:userId:weekStart:)`.
    @State private var wrap: WeeklyWrap.Summary?
    /// The programme as it stood in the week being read — for the wrap's day
    /// labels, and nothing else.
    @State private var program = Program(id: "", label: "", days: [])

    /// A box, because `ReportRow` conforms to neither `Identifiable` nor
    /// `Hashable` and `navigationDestination(item:)` wants the latter. A
    /// retroactive conformance would reach every caller in `OnyxData` for one
    /// destination here — the same box, for the same reason, as
    /// `HistoryView.JumpDate` and `WorkoutTabView.WrapDoor`. Both sides key on
    /// the row's id, which is what identity means for a report anyway.
    private struct ReportDoor: Hashable {
        let report: ReportRow
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.report.id == rhs.report.id }
        func hash(into hasher: inout Hasher) { hasher.combine(report.id) }
    }
    /// `Hashable` since W4, for the same reason `ReportDoor` above it is:
    /// `navigationDestination(item:)` wants it, and the week start already
    /// names a week uniquely.
    private struct WrapDoor: Hashable {
        let summary: WeeklyWrap.Summary
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.summary.weekStart == rhs.summary.weekStart }
        func hash(into hasher: inout Hasher) { hasher.combine(summary.weekStart) }
    }

    @State private var openReport: ReportDoor?
    @State private var wrapDoor: WrapDoor?
    @State private var writingReport = false

    var body: some View {
        List {
            if let detail {
                Section {
                    WeekHeroCard(vitals: detail.vitals, isLive: window.isCurrent)
                        .listRowInsets(.init(top: OnyxSpace.s, leading: OnyxSpace.l,
                                             bottom: OnyxSpace.s, trailing: OnyxSpace.l))
                }
                .listRowBackground(Color.clear)

                actions(detail)

                Section {
                    WeekVitalsRow(vitals: detail.vitals)
                        .listRowInsets(.init(top: OnyxSpace.s, leading: OnyxSpace.l,
                                             bottom: OnyxSpace.s, trailing: OnyxSpace.l))
                }
                .listRowBackground(Color.clear)

                Section {
                    ForEach(detail.days) { day in
                        NavigationLink {
                            DayScreen(model: DayModel(
                                database: environment.database,
                                userId: environment.userIdString,
                                date: day.date,
                                environment: environment
                            ))
                        } label: {
                            DayHistoryRow(day: day)
                        }
                        // ── THE SPLIT'S COLOUR, ON THE ROW AND NOT IN IT ────
                        // `listRowBackground` and not a modifier on the label:
                        // a `.plain` List draws its disclosure chevron OUTSIDE
                        // the label's frame, so a wash applied to the label is
                        // a tinted band that stops short of the row's trailing
                        // edge with a chevron floating on black beside it.
                        // The row background spans the whole row, chevron
                        // included, and iOS draws its own selection highlight
                        // over it — which is why this row needs no `onyxPress`.
                        //
                        // `.onyxGlass(.row)` FIRST, and that is not decoration:
                        // `OnyxMuscleWash`'s own header justifies 6 % → 2 % by
                        // the material it sits behind. On a bare ground the
                        // same gradient reads two to three times more
                        // chromatic than it does on any shipped exercise card.
                        // `.row` and not `.tile` — seven hairlined tiles down
                        // one screen is a box around every box.
                        // The background fills the WHOLE row rect and is not
                        // inset by `listRowInsets`, so it has to repeat them —
                        // one constant, or the band drifts off the row the
                        // first time either is tuned.
                        .listRowInsets(Self.dayRowInsets)
                        .listRowSeparator(.hidden)
                        .listRowBackground(
                            Color.clear
                                .onyxGlass(.row)
                                .onyxMuscleWash(Self.wash(day), corner: OnyxCorner.row)
                                .padding(Self.dayRowInsets)
                        )
                    }
                } header: {
                    OnyxSectionHeader("Days", .train)
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(OnyxSpace.l)
        .scrollContentBackground(.hidden)
        .onyxScreen(.train)
        .tint(OnyxDomain.train.accent)
        .navigationTitle(window.label(in: environment.targets?.schedule))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(window.label(in: environment.targets?.schedule)).onyxType(.body).foregroundStyle(Color.onyx.textPrimary)
                    Text(window.rangeLabel).onyxType(.micro).foregroundStyle(Color.onyx.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        // All three of these hang off the LIST and not off a row or a Section.
        // A `.plain` List is lazy: scroll seven day rows on a small phone and
        // the chip row is torn down, taking any presentation declared on it.
        // `HistoryView` attaches its own jump sheet at this level for the same
        // reason, and a `navigationDestination` declared inside `if let detail`
        // registers and unregisters as the data arrives, which drops the push.
        .navigationDestination(item: $openReport) { door in
            ReportReaderView(report: door.report, week: reportWeek)
        }
        // A PUSH since W4, and still hanging off the LIST for the reason
        // above: the chip that opens it lives in a row, and a `.plain` List
        // tears rows down.
        .navigationDestination(item: $wrapDoor) { door in
            WeeklyReportView(summary: door.summary, program: program)
        }
        .sheet(isPresented: $writingReport) {
            // Re-read on save, or the chip that just wrote a report goes on
            // offering to write one: `.task(id:)` keys on the rescore
            // generation, and writing a report does not move it.
            ReportEditorSheet(week: reportWeek) { _ in
                loadedAt = -1
                Task { await load() }
            }
        }
        .overlay { if detail == nil { ProgressView() } }
        .task(id: environment.rescoreGeneration) { await load() }
    }

    /// The day rows' own insets. `nonisolated` because a `static let` on a
    /// `View` is inferred `@MainActor`, which traps at runtime the first time
    /// anything reads it off the main actor — the W1a `WeeklyMuscleRing` crash.
    nonisolated static let dayRowInsets = EdgeInsets(
        top: 2, leading: OnyxSpace.l, bottom: 2, trailing: OnyxSpace.l
    )

    /// The day's own hue, or nothing at all.
    ///
    /// Two days get no wash, for two different reasons that would otherwise
    /// render identically. A day with no session has no colour to wear —
    /// `Color.onyx.day(_:)`'s own rule is that a rest day wears no accent — and
    /// a coloured rail on a day nothing happened on is a claim.
    ///
    /// The second is the one worth the guard: `day(_:)` answers `textTertiary`
    /// for any split key THIS BUILD does not know, so a logged session from a
    /// custom routine would take a grey wash and a grey rail and come out
    /// looking exactly like a rest day. A session drawn as a rest day is the
    /// one lie this screen must not tell. Same sentinel test `dayLabel` makes.
    ///
    /// `.clear` rather than an optional and a branch: `clear.opacity(0.06)` is
    /// still clear and a rail of two clears is invisible, so the modifier
    /// applies unconditionally and every row keeps one view identity.
    private static func wash(_ day: HistoryWeeks.DayRow) -> Color {
        guard day.isLogged else { return .clear }
        let hue = Color.onyx.day(day.dayKey)
        return hue == Color.onyx.textTertiary ? .clear : hue
    }

    /// This window as the reports list files it, for the reader and the editor.
    private var reportWeek: ReportWeek {
        ReportWeek(start: window.start, end: window.end,
                   report: detail?.report, isCurrent: window.isCurrent)
    }

    // MARK: - Actions

    @ViewBuilder
    private func actions(_ detail: HistoryWeeks.WeekDetail) -> some View {
        Section {
            // ── THE ACTIONS ARE CHIPS NOW, AND ONE OF THEM IS NOT A BUTTON ──
            // `ShareLink` is a VIEW and not an action: it needs its item up
            // front and builds its own button, so a share cannot travel inside
            // `chips` as an `OnyxChip`. It takes the row's own pinned slot
            // instead, wearing `OnyxChipRow.face` — the row's real capsule,
            // made public for exactly this — rather than a hand-rolled one that
            // looks the same until a token moves.
            OnyxChipRow(chips(detail)) { exportChip }
            // The chip row carries its own leading and trailing gutter, so the
            // row's default insets would lay a second one over it and push the
            // chips off the 16 pt line the two tiles above them sit on. Zero
            // sides, and the vertical stays — the chips are a bare 44 pt with
            // no padding of their own and would otherwise touch both tiles.
            .listRowInsets(.init(top: OnyxSpace.s, leading: 0, bottom: OnyxSpace.s, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            // Three chips fit a 375 pt screen. Without this the row rubber-bands
            // on a drag that has nowhere to go, which reads as a broken scroll.
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        } footer: {
            // Spelled rather than inherited. A `.plain` List draws a section
            // footer at body weight, which under a row of 13 pt chips made the
            // explanation louder than the controls it explains.
            Text(detail.report == nil
                 ? "No weekly report has been written for these dates yet."
                 : "The report is the pasted-back brief; the export is what it was written from.")
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.textSecondary)
                .padding(.horizontal, OnyxSpace.l)
                .padding(.top, OnyxSpace.xs)
        }
        .listSectionSeparator(.hidden)
    }

    /// The export, in the row's pinned slot in BOTH states.
    ///
    /// Pinned rather than in `chips` because when it works it is not a `Button`
    /// at all — `ShareLink` is a view that needs its item up front — and pinned
    /// in the LOCKED state too, because a control that moves from the middle of
    /// a row to its end depending on whether it is available is two controls as
    /// far as a reader is concerned. Same slot, same place, one of two faces.
    @ViewBuilder
    private var exportChip: some View {
        if weekIsComplete, let exportFile {
            ShareLink(
                item: exportFile,
                subject: Text("\(window.label(in: environment.targets?.schedule)) · \(window.rangeLabel)"),
                preview: SharePreview(exportFile.lastPathComponent)
            ) {
                OnyxChipRow.face(title: "Export", systemImage: "square.and.arrow.up")
            }
            .onyxPress()
            // `face` is a label, not a `Button`, so it carries none of the
            // accessibility `OnyxChipRow.button` applies for the chips.
            .accessibilityLabel("Export week")
        } else if !weekIsComplete {
            // ── EXPORT IS A CLOSING RITUAL, NOT A LIVE ONE ─────────────────
            // The web has refused this on a running week since the loop was
            // built (`PathfinderTimeline`): an export of a week with days left
            // to log is a partial record, and any report written from it then
            // sits in the ledger looking final.
            //
            // The absence is STATED rather than silent, and it is stated by the
            // control itself. A chip that vanished would read as a bug, and the
            // answer to "where did the button go" is a date — so the chip stays,
            // wears a lock, carries the date in its own title and refuses the
            // tap. A real `Button` so VoiceOver announces it dimmed.
            Button {} label: {
                OnyxChipRow.face(
                    title: "Export opens \(Swap.shortDayLabel(ISODate.addDays(window.start, 7) ?? window.start))",
                    systemImage: "lock", isEnabled: false
                )
            }
            .disabled(true)
        }
    }

    /// Wrapped · Report, with the export pinned beside them.
    ///
    /// ── WHY NONE OF THEM IS PROMINENT ───────────────────────────────────────
    /// `OnyxChipRow`'s own rule reserves the filled capsule for the action that
    /// ENDS the screen, at most one per row. Nothing here ends anything — two
    /// are destinations and the third is a share sheet. Spending prominence
    /// where the rule says not to is how a rule stops being one, and a filled
    /// capsule eight points under the hero would be a second loudest thing on a
    /// screen that just acquired its first. The wrap chip takes the train
    /// accent instead, which is one step of emphasis and no second hero.
    ///
    /// ── AND WHY THE THREE GATES DISAGREE ON PURPOSE ─────────────────────────
    /// The report appears when one has been written and offers the editor when
    /// one has not. The export opens strictly after the week's last calendar
    /// day (`WeekReady.isComplete`). The wrap opens when the week WRAPPED —
    /// every planned training day logged — which on a plan that rests Saturday
    /// can be true on Friday evening. So there is a real two-day window where
    /// the wrap is readable and the export is not, and both of those are right:
    /// the wrap-up is about the training, and a document that claims to be the
    /// week is about the week.
    private func chips(_ detail: HistoryWeeks.WeekDetail) -> [OnyxChip] {
        var out: [OnyxChip] = []
        // Leftmost, because it is the reason someone opens a week that closed a
        // month ago: the narrative, not the utilities beside it.
        // ── ONE WORD EACH, AND THAT IS A MEASUREMENT ───────────────────────
        // "Week wrapped", "Write report" and "Export week" come to roughly
        // 377 pt of capsule on a 375 pt phone, so the middle chip photographed
        // sliced by the row's own fade. The screen these sit on is titled with
        // the week and nothing else here is about anything but the week, so the
        // word "week" in a chip is paid for three times and earns nothing.
        if let wrap {
            out.append(.init(
                title: "Wrapped", systemImage: "sparkles",
                tint: OnyxDomain.train.accent
            ) { wrapDoor = WrapDoor(summary: wrap) })
        }
        // One title across both states, two glyphs. A control whose LABEL
        // changes when its state does reads as a different control; a pencil
        // where a page was says the same thing without the row resizing.
        if let report = detail.report {
            out.append(.init(title: "Report", systemImage: "doc.text") {
                openReport = ReportDoor(report: report)
            })
        } else {
            out.append(.init(title: "Report", systemImage: "square.and.pencil") {
                writingReport = true
            })
        }
        // The export is not here — it lives in the row's pinned slot in both
        // of its states, because it is a `ShareLink` when it works. See
        // `exportChip`.
        return out
    }


    /// Strictly after this week's final day, in the device's own calendar —
    /// the same rule the web's export gate reads.
    private var weekIsComplete: Bool {
        // `environment.today` and not a fresh clock read: it is the app's one
        // answer to "what day is it", and it is observed — so a week that
        // closes while this screen is open opens its export without a reload.
        WeekReady.isComplete(weekStart: window.start, today: environment.today)
    }

    // MARK: - Loading

    private func load() async {
        if let seeded {
            detail = seeded
            return
        }
        /* ── THE LEDGER IS CACHED; THE EXPORT IS NOT ──────────────────────────
           This guard used to cover the whole method, so the document was
           rebuilt only when a rescore cascade had finished. `rescoreGeneration`
           moves for a set edit and a scored day — it does NOT move for a
           supplement tick, a joint flag, a cardio bout, a stress reading, or a
           sync PULL bringing another device's edit down. Any of those left
           `exportFile` pointing at the PREVIOUS `onyx-week-<date>.md` still
           sitting in the temporary directory, so the share sheet handed over a
           stale document that looked current.

           The week's ledger is genuinely expensive and genuinely only changes
           on a rescore, so it keeps the guard. The export is rebuilt on every
           appearance: it is one read and one file write against a closed week,
           and a wrong document is worse than a redundant render. */
        let rebuildDetail = loadedAt != environment.rescoreGeneration
        loadedAt = environment.rescoreGeneration
        let database = environment.database
        let userId = environment.userIdString
        let window = self.window
        let current = detail
        let built = await Task.detached(priority: .userInitiated) { () -> Built in
            let detail = rebuildDetail ? HistoryWeeks.detail(database: database, window: window) : nil
            let input = try? WeeklyExportBuilder(database: database, userId: userId)
                .input(weekStart: window.start)
            let text = input.map { WeeklyExport.build($0) }
            // ── THE WRAP RIDES WITH THE LEDGER, NOT WITH THE DOCUMENT ───────
            // Both of the others are already here and the guardrail is to add
            // no second read pass, so it folds into this task. It follows
            // `rebuildDetail` and NOT the export's rebuild-every-appearance
            // rule, because the two are different costs: the export is one read
            // and one file write, while `wrap` replays the record book once per
            // session in the week (its own header says so, and marks it
            // `ponytail:`). What it reads — sets, sessions, PRs — is exactly
            // what moves `rescoreGeneration`, so the guard is also correct and
            // not merely cheap.
            let wrap = rebuildDetail
                ? WorkoutWeek.wrap(database, userId: database.localUserId(), weekStart: window.start)
                : nil
            // Read inside the task, off `database`, rather than reaching for
            // `environment` from a closure that deliberately captures no `self`.
            let program = rebuildDetail
                ? (try? database.scheduleContext(userId: database.localUserId(), today: window.start))?.activeProgram
                : nil
            return Built(detail: detail, export: text, wrap: wrap, program: program)
        }.value
        if let fresh = built.detail { detail = fresh } else if current == nil { return }
        exportFile = built.export.flatMap { Self.writeExport($0, weekStart: window.start) }
        // ── GATED ON WHETHER THE PASS RAN, NOT ON WHAT IT RETURNED ──────────
        // `detail` can use `if let` because `HistoryWeeks.detail` never returns
        // nil — nil there means only "the guard skipped it". For the wrap, nil
        // is a REAL answer: the week no longer qualifies. Writing `if let` here
        // would conflate the two, and the failure is worse than a flicker —
        // delete a session from a week that had wrapped and the rescore
        // correctly rebuilds `nil`, which `if let` would discard, leaving the
        // chip up and opening a reel that still counts the deleted work.
        if rebuildDetail {
            wrap = built.wrap
            program = built.program ?? program
        }
    }

    /// What one detached pass produces. A named shape rather than a 4-tuple so
    /// the call site reads as words instead of `built.0`.
    private struct Built: Sendable {
        var detail: HistoryWeeks.WeekDetail?
        var export: String?
        var wrap: WeeklyWrap.Summary?
        var program: Program?
    }

    /// The document, on disk, under a name a reader can file.
    ///
    /// The temporary directory and not the App Group: this is a hand-off to the
    /// share sheet and nothing else reads it. The file is REWRITTEN on every
    /// load rather than appended to or suffixed, so re-exporting the same week
    /// twice leaves one file rather than a drawer of near-identical ones.
    private static func writeExport(_ markdown: String, weekStart: String) -> URL? {
        // `2026-08-30` → `onyx-week-2026-08-30.md`. The date and not the week
        // NUMBER: a number is only meaningful inside one programme, and a file
        // outlives the programme it came from.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("onyx-week-\(weekStart).md")
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            // A share that cannot be written is a button that does nothing, so
            // the row disappears rather than presenting an empty sheet.
            return nil
        }
    }
}

// MARK: - The hero

/// The four figures a week is opened for, above the eight it is scanned with.
///
/// ── WHY A HERO AT ALL, ON A SCREEN THAT ALREADY HAD EIGHT NUMBERS ───────────
/// `WeekVitalsRow` is a REGISTER: eight equal cells, no ranking, built to be
/// scanned for the one you came for. That is the right shape for a register and
/// the wrong shape for an answer. A week has a headline — what it weighed, what
/// it moved, what it cost — and a register cannot say which of its eight cells
/// that is, because saying so is precisely what it refuses to do.
///
/// ── AND WHY THE TYPE SCALE DOES THE RANKING ─────────────────────────────────
/// Four figures at `.display` (20 pt) over eight at `.secondary` (15 pt) is the
/// weakest step on the whole scale, and it would have read as sixteen numbers in
/// two paragraphs rather than a headline and its detail. So tonnage takes
/// `.hero` — the one 28 pt figure this screen is allowed and had never spent —
/// and the three that qualify it sit at `.display` beneath. 28 / 20 / 15 is
/// three real steps, and it costs no new token.
///
/// The strain cell carries ACWR as its sub-caption, the way tonnage carries its
/// delta in the register below: one cell, two figures, because a load number
/// without the ratio it sits at is half a sentence.
struct WeekHeroCard: View {
    let vitals: HistoryWeeks.WeekVitals
    /// Is this the week being lived? It changes what the load figures MEAN.
    let isLive: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    private struct Entry: Identifiable {
        let id: String
        let value: String?
        let sub: String?
        let domain: OnyxDomain
    }

    /// The three that qualify the headline. Tonnage is not among them — it is
    /// the headline, and printing it twice would be the proofreading error this
    /// card exists to avoid.
    private var entries: [Entry] {
        [
            Entry(id: "Avg weight",
                  value: vitals.weightMeanKg.map { "\($0.formatted(.number.precision(.fractionLength(1)))) kg" },
                  sub: nil, domain: .body),
            Entry(id: "Strain",
                  // Raw Foster strain is the first one this app has ever shown
                  // — every other consumer renders `strainZ` or the clamped
                  // drain term — so there is no convention to match. A whole
                  // number with a thousands separator: it runs to four digits
                  // and its decimals are noise at this size.
                  value: vitals.strain.map { Int(jsRound($0)).formatted() },
                  // ── THE SUB QUALIFIES THE VALUE, SO IT NEEDS ONE ────────
                  // The two figures have independent nil rules and they do
                  // diverge: `fosterWeek` has no monotony when the week's seven
                  // loads are equal — an untrained week, every one of them
                  // zero — while the ratio survives, because its EWMA runs over
                  // the whole 49-day series. Printing "ACWR 0.18" under a dash
                  // is a caption explaining a figure that is not there.
                  //
                  // Two places and not the export's three. That file is a
                  // document to be read closely; this is a 13 pt caption under
                  // a 20 pt number, and the third digit is unreadable there.
                  sub: vitals.strain == nil ? nil
                      : vitals.acwr.map { "ACWR \($0.formatted(.number.precision(.fractionLength(2))))" },
                  domain: .recover),
            Entry(id: "Fat", value: delta(vitals.fatDeltaPct, unit: "%"), sub: nil, domain: .body),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.l) {
            headline
            // The same collapse `WeekVitalsRow` makes, and deliberately NOT
            // `ViewThatFits`: every cell here carries `.frame(maxWidth:
            // .infinity)`, which tells `ViewThatFits` the row fits any width, so
            // it takes the first candidate at every size and the stacked branch
            // is dead code. That is the W4 defect, and it is a property of the
            // frame rather than of the size class.
            if typeSize.isAccessibilitySize {
                VStack(spacing: OnyxSpace.m) {
                    ForEach(entries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
                            label(entry.id)
                            Spacer(minLength: OnyxSpace.s)
                            VStack(alignment: .trailing, spacing: 2) {
                                value(entry)
                                sub(entry)
                            }
                        }
                    }
                }
            } else {
                HStack(alignment: .top, spacing: OnyxSpace.s) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            label(entry.id)
                            value(entry)
                            sub(entry)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            // Only when there is a load figure for it to qualify — and that is
            // exactly `strain`, since the ratio is bound to it above. A note
            // explaining how a dash was arrived at is a note about nothing.
            if isLive, vitals.strain != nil { liveNote }
        }
        // `OnyxSpace.l` and not the register's `m`: whitespace per figure is
        // half of what makes this card outrank the one under it. Same padding
        // as the tile below would be the same object twice.
        .padding(OnyxSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onyxGlass(.tile)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            label("Tonnage")
            Text(vitals.tonnageKg > 0 ? "\(Format.volume(vitals.tonnageKg)) kg" : "—")
                .onyxType(.hero)
                .onyxNumeral()
                .foregroundStyle(vitals.tonnageKg > 0 ? OnyxDomain.train.accent : Color.onyx.textTertiary)
                .lineLimit(1)
                // More headroom than the register's 0.7: at 28 pt an AX5 line
                // has further to fall before it fits, and a tonnage that wraps
                // mid-number is worse than one that shrinks.
                .minimumScaleFactor(0.6)
                .accessibilityElement()
                .accessibilityLabel("Tonnage, \(vitals.tonnageKg > 0 ? "\(Format.volume(vitals.tonnageKg)) kilograms" : "no sessions")")
        }
    }

    /// Said once, on the live week only.
    ///
    /// `HistoryWeeks.detail` reads the load series to TODAY rather than to the
    /// week's end, because days that have not happened enter as real zeros and
    /// would decay the ratio into a detraining signal. That clamp is what a
    /// reader is owed a word about, and the word has to cover both figures
    /// without claiming the same thing of each: strain IS a seven-day window
    /// and the ratio is not — it is an EWMA over the whole 49-day series, read
    /// at a point. "Read to today" is true of both; "covers seven days" was
    /// true of only one.
    private var liveNote: some View {
        Text("Training load is read to today, not to the end of the week — this week is still open.")
            .onyxType(.micro)
            .foregroundStyle(Color.onyx.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .onyxType(.micro)
            .foregroundStyle(Color.onyx.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }

    private func value(_ entry: Entry) -> some View {
        Text(entry.value ?? "—")
            .onyxType(.display)
            // The register's numbers are rounded and these are the larger ones;
            // without this the hero would be the only figures on the screen in
            // the default face.
            .onyxNumeral()
            .foregroundStyle(entry.value == nil ? Color.onyx.textTertiary : entry.domain.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityElement()
            .accessibilityLabel("\(entry.id), \(entry.value ?? "no reading")\(entry.sub.map { ", \($0)" } ?? "")")
    }

    @ViewBuilder
    private func sub(_ entry: Entry) -> some View {
        if let sub = entry.sub {
            Text(sub)
                .onyxType(.caption)
                .onyxNumeral()
                .foregroundStyle(Color.onyx.textSecondary)
                // Allowed to WRAP rather than capped at one line. At AX5 this
                // sits in the trailing half of a collapsed row and "ACWR 1.07"
                // came out as "ACWR 1...." — a scale factor cannot save a
                // string this short, and an elided figure is worse than one
                // that takes a second line.
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
    }

    /// A delta always carries its sign — the same rule, and the same reason, as
    /// the register below: an unsigned 0.4 in a cut is the opposite news.
    private func delta(_ value: Double?, unit: String) -> String? {
        guard let value else { return nil }
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(value.formatted(.number.precision(.fractionLength(1)))) \(unit)"
    }
}

// MARK: - The 2×4

/// Eight cells over two rows: what the body did, what recovery did, and what
/// the training added up to.
///
/// Every value is optional and a missing one renders `—`. A week with no
/// weigh-in has no delta, and a `0.0 kg` in that slot is a claim that the
/// weight held steady.
struct WeekVitalsRow: View {
    let vitals: HistoryWeeks.WeekVitals

    @Environment(\.dynamicTypeSize) private var typeSize

    private struct Entry: Identifiable {
        let id: String
        let value: String?
        let domain: OnyxDomain
    }

    private var entries: [Entry] {
        [
            Entry(id: "Weight", value: delta(vitals.weightDeltaKg, unit: "kg", places: 1), domain: .body),
            Entry(id: "Fat", value: delta(vitals.fatDeltaPct, unit: "%", places: 1), domain: .body),
            Entry(id: "Battery", value: vitals.batteryMean.map { jsIntegerString(jsRound($0)) }, domain: .recover),
            Entry(id: "Sleep score", value: vitals.sleepScoreMean.map { jsIntegerString(jsRound($0)) }, domain: .recover),
            Entry(id: "Sleep", value: vitals.sleepMeanMinutes.map(Self.hours), domain: .recover),
            Entry(id: "Steps", value: vitals.stepsMean.map { jsIntegerString(jsRound($0)) }, domain: .body),
            Entry(id: "Tonnage", value: vitals.tonnageKg > 0 ? "\(Format.volume(vitals.tonnageKg)) kg" : nil, domain: .train),
            Entry(id: "Sessions", value: "\(vitals.sessions)", domain: .train),
        ]
    }

    var body: some View {
        Group {
            // ── WHY IT STOPS BEING A GRID ───────────────────────────────────
            // Two columns at AX5 gave every cell half a phone to hold a label
            // AND a number: "Tonnage" hyphenated into "Ton-nage" and
            // "12,510.0 kg" truncated to "12,510…" — a figure shown as an
            // ellipsis is worse than one not shown. At accessibility sizes the
            // eight become eight rows, label leading and number trailing, which
            // is what every other list in this app already does.
            if typeSize.isAccessibilitySize {
                VStack(spacing: OnyxSpace.m) {
                    ForEach(entries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
                            label(entry)
                            Spacer(minLength: OnyxSpace.s)
                            value(entry)
                        }
                    }
                }
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: OnyxSpace.s), count: 4),
                    spacing: OnyxSpace.m
                ) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            label(entry)
                            value(entry)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(OnyxSpace.m)
        .onyxGlass(.tile)
    }

    private func label(_ entry: Entry) -> some View {
        Text(entry.id)
            .onyxType(.micro)
            .foregroundStyle(Color.onyx.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }

    private func value(_ entry: Entry) -> some View {
        Text(entry.value ?? "—")
            .onyxType(.secondary)
            .onyxNumeral()
            .foregroundStyle(entry.value == nil ? Color.onyx.textTertiary : entry.domain.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityElement()
            .accessibilityLabel("\(entry.id), \(entry.value ?? "no reading")")
    }

    /// A delta always carries its sign — `+0.4`, `−0.9` — because the sign IS
    /// the reading. An unsigned 0.4 in a cut is the opposite news.
    private func delta(_ value: Double?, unit: String, places: Int) -> String? {
        guard let value else { return nil }
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(value.formatted(.number.precision(.fractionLength(places)))) \(unit)"
    }

    private static func hours(_ minutes: Double) -> String {
        let total = Int(jsRound(minutes))
        return "\(total / 60)h \(String(format: "%02d", total % 60))m"
    }
}

// MARK: - A day

/// `Thu 3 Sep · Chest & Back A` and what it held.
struct DayHistoryRow: View {
    let day: HistoryWeeks.DayRow

    var body: some View {
        HStack(spacing: OnyxSpace.m) {
            // The same three states the capsule strip draws, so a day that is
            // a speck there is a speck here: logged, planned-and-not, rest.
            Group {
                if day.isLogged {
                    Circle().fill(Color.onyx.day(day.dayKey))
                } else if day.dayKey == nil {
                    Circle()
                        .fill(Color.onyx.textTertiary.opacity(0.5))
                        .frame(width: 4, height: 4)
                } else {
                    Circle().strokeBorder(Color.onyx.day(day.dayKey).opacity(day.isFuture ? 0.35 : 0.8), lineWidth: 1.5)
                }
            }
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(SessionRow.date(day.date))
                    .foregroundStyle(day.isFuture ? Color.onyx.textTertiary : Color.onyx.textPrimary)
                Text(title)
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textSecondary)
            }

            Spacer(minLength: OnyxSpace.s)

            VStack(alignment: .trailing, spacing: 2) {
                if day.isLogged {
                    Text("\(Format.volume(day.tonnageKg)) kg")
                        .onyxNumeral()
                        .foregroundStyle(Color.onyx.textPrimary)
                }
                Text(meta)
                    .onyxType(.caption)
                    .onyxNumeral()
                    .foregroundStyle(Color.onyx.textSecondary)
            }
        }
        .padding(.vertical, OnyxSpace.xs)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if day.isLogged { return day.label ?? "Session" }
        if day.dayKey == nil { return "Rest" }
        return day.isFuture ? "\(day.label ?? "Planned") · planned" : "\(day.label ?? "Planned") · missed"
    }

    /// Sets and PRs when there was a session; the day's own numbers otherwise,
    /// because a rest day still has sleep and steps worth scanning.
    private var meta: String {
        var parts: [String] = []
        if day.isLogged {
            parts.append("\(day.sets) sets")
            if let minutes = day.durationMin { parts.append("\(jsIntegerString(jsRound(minutes))) min") }
            if day.prCount > 0 { parts.append("\(day.prCount) PR") }
        }
        if let steps = day.steps { parts.append("\(steps.formatted()) steps") }
        if let sleep = day.sleepMinutes { parts.append("\(sleep / 60)h \(String(format: "%02d", sleep % 60))m") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

/// Shared date formatting for every history row.
///
/// Kept as a type rather than folded into the rows: `SessionDetailView` titles
/// itself with the same string, and two spellings of "Thu 3 Sep" on a page and
/// the row that opened it is the kind of drift nobody notices until a month
/// abbreviation changes.
enum SessionRow {
    static func date(_ iso: String) -> String {
        LogicalDay.date(fromISO: iso).map {
            $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        } ?? iso
    }
}

#if DEBUG
#Preview("Week") { HistoryPreviews.view("history-week") }
#endif
