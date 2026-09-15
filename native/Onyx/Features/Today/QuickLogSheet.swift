import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

/// Six things you log about today, one tap from the dashboard (decision 5).
///
/// ── WHAT THE MARK WAS, AND WHAT IT IS NOW ───────────────────────────────────
/// The Onyx mark in the top-right of Today has always been decoration —
/// `.accessibilityHidden`, the wordmark's other half, the one place the ring
/// appears at app scale. It is the most reachable point on the busiest screen
/// in the app and it did nothing. The six readings behind it were each three
/// or four taps away on another tab: water on Nutrition, weight and fatigue and
/// soreness on Pulse, a cardio bout on Workout.
///
/// "Done" still owns that slot in edit mode. A control that both ends the
/// jiggle and opens a logger is a control you cannot tap in one of the two
/// states without meaning the other.
///
/// ── WHY A RING AND NOT A MENU ───────────────────────────────────────────────
/// A `Menu` of six is six rows read top to bottom, and reading is what this is
/// meant to avoid: these are six SHAPES in six fixed places, and the fourth or
/// fifth time you log water your thumb goes there without your eyes. Fixed
/// positions is the whole value, so the ring never reorders by recency.
///
/// Every spoke opens a sheet that already existed. The one exception is water,
/// which commits on the tap and leaves the ring standing — see `waterDetail`.
struct QuickLogSheet: View {
    let model: DayModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var opening: Destination?
    @State private var glasses = 0

    /// The sheet a spoke opens. `Identifiable` so one `.sheet(item:)` presents
    /// all five — five `isPresented` flags on one view is five ways for two
    /// sheets to try to present at once.
    private enum Destination: String, Identifiable {
        case weighIn, fatigue, stress, cardio, note
        var id: String { rawValue }
    }

    /// A spoke: what it is, what it draws, and what it says today.
    private struct Spoke: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
        let domain: OnyxDomain
        let action: () -> Void
    }

    var body: some View {
        NavigationStack {
            Group {
                // Six 60 pt circles on a ring cannot grow with the type scale
                // without overlapping each other, and a ring whose labels are
                // clipped is a ring you cannot learn. At an accessibility size
                // the same six become a list, which is what they are.
                if typeSize.isAccessibilitySize { column } else { ring }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The only spoke that writes without opening anything is the only
            // one with no sheet to confirm it. The count is what the haptic
            // fires on, so a second glass feels like a second glass.
            .sensoryFeedback(.success, trigger: glasses)
            .onyxScreen(.recover)
            .navigationTitle("Quick Log")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Text(dayLabel)
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .padding(.bottom, OnyxSpace.s)
                    .accessibilityLabel("Logging against \(dayLabel)")
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(OnyxDomain.recover.accent)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(Self.ringBox + Self.ringChrome)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.onyx.base)
        .preferredColorScheme(.dark)
        .sheet(item: $opening) { destination in
            switch destination {
            case .weighIn: InBodyEntryView(model: model)
            case .fatigue: FatigueSheet(model: model)
            case .stress:  StressLogSheet(model: model)
            case .note:    DayNoteSheet(model: model)
            case .cardio:
                CardioLogSheet(
                    userId: model.userId, date: model.date,
                    existing: model.cardio,
                    onSave: { model.addCardio($0) }
                )
            }
        }
    }

    // MARK: - The six

    private var spokes: [Spoke] {
        [
            Spoke(id: "water", symbol: "drop.fill", title: "Water", detail: waterDetail, domain: .fuel) {
                if model.addWaterGlass(Self.glassMl) { glasses += 1 }
            },
            Spoke(id: "weighIn", symbol: "scalemass", title: "Weigh-in", detail: weightDetail, domain: .body) {
                opening = .weighIn
            },
            Spoke(id: "fatigue", symbol: "battery.50", title: "Fatigue", detail: fatigueDetail, domain: .recover) {
                opening = .fatigue
            },
            Spoke(id: "stress", symbol: "brain.head.profile", title: "Stress", detail: stressDetail, domain: .recover) {
                opening = .stress
            },
            Spoke(id: "cardio", symbol: "figure.run", title: "Cardio", detail: cardioDetail, domain: .train) {
                opening = .cardio
            },
            Spoke(id: "note", symbol: "square.and.pencil", title: "Note", detail: noteDetail, domain: .body) {
                opening = .note
            },
        ]
    }

    /// A glass, not a total.
    ///
    /// Water is the only one of the six that is the same action every time and
    /// carries no information beyond "again", so it is the only one that does
    /// not need a form — and a form for it would make the most repeated write
    /// in the app the slowest. The tap adds a ledger row and the label counts
    /// up under the thumb, so a second and third glass are a second and third
    /// tap without the ring ever closing.
    static let glassMl: Double = 250
    /// The square the ring is laid out in. The DETENT has to hold this plus the
    /// navigation bar — sized at the ring box alone, the bottom spoke's detail
    /// line was cut off by the sheet's own edge.
    private static let ringBox: CGFloat = 320
    private static let ringChrome: CGFloat = 96

    // ── EIGHTY-FOUR POINTS IS ONE WORD ──────────────────────────────────────
    // A spoke is as wide as two of its neighbours will allow, and "Nothing
    // written" came out as "NOTHING…" — a label that says less than the em dash
    // this app already uses everywhere for "no reading" (`DayFormat.number`).
    // Every empty state is that dash; every filled one is one word or one
    // figure.

    private var waterDetail: String {
        guard let ml = model.waterMl, ml > 0 else { return "+250 ml" }
        return "\(DayFormat.number(ml / 1000)) L"
    }

    private var weightDetail: String {
        model.log?.weightKg.map { DayFormat.number($0, unit: "kg") } ?? "—"
    }

    private var fatigueDetail: String {
        Fatigue.latest(model.fatigue).flatMap { Fatigue.level($0.level)?.label } ?? "—"
    }

    /// The LATEST reading, never the day's mean — the same choice the stress
    /// log card makes, for the same reason: a spoke that said "3.0" on a day
    /// you answered Relaxed at breakfast and Swamped at midnight would describe
    /// neither moment.
    private var stressDetail: String {
        model.stressLatest.flatMap { PsychStress.level($0.level)?.label } ?? "—"
    }

    private var cardioDetail: String {
        let bouts = model.cardio.count
        return bouts == 0 ? "—" : "\(bouts) bout\(bouts == 1 ? "" : "s")"
    }

    /// Which day the ring is writing to, said once. Six spokes that file
    /// against a date nobody named is how an app left open across midnight logs
    /// tomorrow's water against yesterday.
    private var dayLabel: String {
        guard let date = LogicalDay.date(fromISO: model.date) else { return model.date }
        return model.isToday
            ? "Today · \(date.formatted(.dateTime.day().month(.abbreviated)))"
            : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private var noteDetail: String { model.note.isEmpty ? "—" : "Written" }

    // MARK: - The ring

    /// Six spokes, 60° apart, the first at twelve o'clock. Fixed positions: a
    /// ring that reorders is a ring nobody learns.
    private var ring: some View {
        // Nothing in the middle. A mark there is a ring inside a ring, and at
        // 40 pt it reads as a progress spinner — which is the one thing a
        // control surface must never look like.
        ZStack {
            ForEach(Array(spokes.enumerated()), id: \.element.id) { index, spoke in
                let angle = Angle.degrees(Double(index) / Double(spokes.count) * 360 - 90)
                target(spoke)
                    .offset(
                        x: Self.radius * CGFloat(cos(angle.radians)),
                        y: Self.radius * CGFloat(sin(angle.radians))
                    )
            }
        }
        .frame(width: Self.ringBox, height: Self.ringBox)
        .accessibilityElement(children: .contain)
    }

    private static let radius: CGFloat = 100

    private func target(_ spoke: Spoke) -> some View {
        Button(action: spoke.action) {
            VStack(spacing: OnyxSpace.xs) {
                ZStack {
                    Circle().fill(.ultraThinMaterial)
                    Circle().strokeBorder(Color.onyx.hairline, lineWidth: 0.5)
                    Image(systemName: spoke.symbol)
                        .onyxType(.display).fontWeight(.medium)
                        .foregroundStyle(spoke.domain.accent)
                }
                .frame(width: 60, height: 60)
                Text(spoke.title)
                    .onyxType(.caption).fontWeight(.semibold)
                    .foregroundStyle(Color.onyx.textPrimary)
                    .lineLimit(1)
                Text(spoke.detail)
                    // `.onyxMicro()` is the UPPERCASE label style ("SCORE") and
                    // this is a value, not a label — and uppercase costs about
                    // a fifth of the width a spoke has.
                    .onyxType(.micro)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .lineLimit(1)
            }
            // Wider than the circle so the two labels have somewhere to go, and
            // narrow enough that two neighbours on the ring do not touch.
            .frame(width: 84)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onyxPress(scale: 0.94)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoke.title)
        .accessibilityValue(spoke.detail)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - The column

    private var column: some View {
        ScrollView {
            VStack(spacing: OnyxSpace.s) {
                ForEach(spokes) { spoke in
                    Button(action: spoke.action) {
                        HStack(spacing: OnyxSpace.m) {
                            Image(systemName: spoke.symbol)
                                .foregroundStyle(spoke.domain.accent)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(spoke.title).onyxType(.body)
                                Text(spoke.detail)
                                    .onyxType(.caption)
                                    .foregroundStyle(Color.onyx.textSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .padding(OnyxSpace.m)
                        .onyxGlass(.row)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spoke.title)
                    .accessibilityValue(spoke.detail)
                    .accessibilityAddTraits(.isButton)
                }
            }
            .padding(OnyxSpace.l)
        }
    }
}

// MARK: - The note

/// A line about the day, and nothing reads it.
///
/// `daily_logs.journal_md` has been in the schema and in the mirror since the
/// beginning with no writer on either surface. It scores nothing and is an
/// input to nothing — which is the point: everything else on this screen is a
/// measurement that moves a number, and there was nowhere to put "slept badly,
/// flight at six" except into a field that would have been read as data.
struct DayNoteSheet: View {
    let model: DayModel

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var loaded = false
    @FocusState private var typing: Bool

    var body: some View {
        DaySheet(
            "Note",
            domain: .body,
            glass: false,
            detents: [.medium, .large],
            primary: ("Save", true, save)
        ) {
            Form {
                Section {
                    TextField("What happened today", text: $text, axis: .vertical)
                        .lineLimit(3...12)
                        .focused($typing)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Note")
                } footer: {
                    Text("Yours. Nothing scores it, nothing exports it and nothing reads it back at you.")
                }
            }
        }
        // ── THE SAME HAZARD `StressLogSheet` DOCUMENTS ──────────────────────
        // The day's row arrives on a stream, and Quick Log builds its model on
        // the tap — so `onAppear` can fire before the first yield, the editor
        // would open blank over an existing note, and Save would clear
        // `journal_md` on the phone AND on the server (the write names the
        // column in `clearing:`). `onChange` catches the row when it lands, and
        // neither path touches text the reader has started.
        .onAppear(perform: adopt)
        .onChange(of: model.note) { _, _ in adopt() }
    }

    private func adopt() {
        guard !loaded, !model.note.isEmpty, text.isEmpty else { return }
        loaded = true
        text = model.note
    }

    private func save() {
        if model.setNote(text) { dismiss() }
    }
}
