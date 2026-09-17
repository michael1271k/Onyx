import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

/// What the scale said this morning, or why it did not.
///
/// ── THREE METRICS THAT ARE NOT THE SAME METRIC ──────────────────────────────
/// `muscle_mass_kg` is LEAN SOFT TISSUE (weight × muscle %, ~50 kg) and is
/// labelled so; skeletal muscle (~27 kg) is the scale's own separate reading.
/// They have shared a label before and it cost the app a season of wrong
/// deltas. No tape measurements: the W:H ratio is one float the scale reports.
///
/// ── AND WHY THIS IS NOW A ROW ───────────────────────────────────────────────
/// The tile drew seven metrics in a grid, a gap sentence, a skip-reason row and
/// a full-width button — a quarter of the screen for a reading taken once a
/// week, most days showing seven em dashes. §5.7 asks for a row: what the last
/// weigh-in said, why there is not one, and the `+` that opens the form. The
/// seven metrics live in the form itself and in Body trends, which is the
/// screen about how they MOVE.
struct ScaleRow: View {
    let model: DayModel
    let onEnter: () -> Void

    @State private var choosingReason = false

    private var log: DailyLogRow? { model.log }

    /// "64.8 kg · 15.2 % fat", or the skip reason, or the invitation.
    private var detail: String {
        if let weight = log?.weightKg {
            var parts = ["\(DayFormat.number(weight)) kg"]
            if let fat = log?.bodyFatPct { parts.append("\(DayFormat.number(fat)) % fat") }
            if let skeletal = log?.skeletalMuscleMassKg { parts.append("\(DayFormat.number(skeletal)) kg SMM") }
            return parts.joined(separator: " · ")
        }
        return "No weigh-in · \(WeighIn.skipReason(log?.weighinSkipReason))"
    }

    var body: some View {
        PulseRow(
            symbol: "scalemass",
            title: "Scale",
            detail: detail,
            spoken: log?.weightKg == nil
                ? "no weigh-in, \(WeighIn.skipReason(log?.weighinSkipReason))"
                : detail,
            action: onEnter
        ) {
            // The reason is only ever offered on a day with no reading, and it
            // is a SECOND control on the row — long-press rather than a second
            // chevron, which would make one row look like two.
            EmptyView()
        }
        .contextMenu {
            Button("Enter InBody reading", systemImage: "square.and.pencil", action: onEnter)
            if log?.weightKg == nil {
                Button("Why no weigh-in…", systemImage: "questionmark.circle") { choosingReason = true }
            }
        }
        .confirmationDialog("Why no weigh-in?", isPresented: $choosingReason, titleVisibility: .visible) {
            ForEach(WeighIn.skipReasons, id: \.self) { reason in
                Button(reason) { model.setWeighInSkipReason(reason) }
            }
        } message: {
            Text("Currently \(WeighIn.skipReason(log?.weighinSkipReason)). \"\(WeighIn.skipReason(nil))\" is the protocol and is not stored.")
        }
    }
}

// MARK: - The InBody form

/// One field on the InBody sheet.
///
/// FILE SCOPE, not nested in `InBodyEntryView`, and neither is `InBodySaveGate`
/// below. A `View` is `@MainActor`-isolated and so is everything declared
/// inside it, including a `CaseIterable` witness — a test that touches
/// `allCases` from a non-isolated context traps at runtime rather than failing
/// to compile, which is the shape that cost W1a a debugging round. The gate is
/// the one piece of this screen worth testing, so it lives where a test can
/// reach it.
enum InBodyField: Hashable, CaseIterable {
    case weight, waist, bmi, bodyFat, muscle, water, protein, bone, visceral, bmr, skeletal, whr
}

/// The save gate, as arithmetic on four dictionaries.
///
/// This is the rule that decides whether an untouched sheet can write a
/// duplicate reading, and there is no screenshot and no simulator that can show
/// it is right. `OnyxTests` exercises it directly — see `InBodySaveGateTests`.
///
///   · `draft` — what the DAY holds plus what the user typed.
///   · `seeded` — the fields the sheet pre-filled from the last reading or from
///     Apple Health. Never merged into `draft`, which is the whole point:
///     merged, every one of them would read as an edit and Save would be live
///     the instant the sheet opened.
///   · `touched` — fields the user has operated, so that clearing a pre-filled
///     field is respected rather than undone.
enum InBodySaveGate {
    static func pendingFields(
        all: [InBodyField],
        stored: [InBodyField: Double],
        draft: [InBodyField: Double],
        seeded: Set<InBodyField>,
        touched: Set<InBodyField>
    ) -> Set<InBodyField> {
        // A real edit: a value that is present and differs from the day's own.
        // A CLEARED field is not an edit — blank stays blank, and Save is not
        // how a column gets emptied.
        let typed = all.filter { draft[$0] != nil && draft[$0] != stored[$0] }
        // With a reading already on the day, the seed is offered for reading and
        // never for writing: a sheet opened and dismissed must not commit a
        // second, identical weigh-in.
        guard stored.isEmpty else { return Set(typed) }
        let offered = all.filter { !touched.contains($0) && draft[$0] == nil && seeded.contains($0) }
        return Set(typed + offered)
    }

    /// The figures a save may derive MASSES from: what the day already holds,
    /// with the fields actually being written laid over the top. Never the seed.
    ///
    /// ── WHY THIS IS NOT JUST "WHAT IS ON SCREEN" ────────────────────────────
    /// The sheet shows seeded values, and `BodyComposition.derive` will happily
    /// turn them into six mass columns. Writing those was a real defect: on a
    /// day holding a weight and nothing else, correcting the WAIST and pressing
    /// Save wrote `fat_mass_kg`, `fat_free_mass_kg`, `muscle_mass_kg`,
    /// `water_mass_kg`, `bone_mineral_kg` and `protein_mass_kg` computed from
    /// LAST WEEK's percentages, while the percentage columns themselves stayed
    /// null. Body trends and the two `OnyxComposition` widget faces read those
    /// mass columns, so the day grew a composition point with nothing behind it.
    ///
    /// A mass may only come from a figure that is itself being written, or that
    /// the day already holds. `derive` returns nil for a missing input, so the
    /// input set IS the gate and there are no per-mass conditionals to keep in
    /// step with it.
    static func massInputs(
        stored: [InBodyField: Double],
        writing: [InBodyField: Double]
    ) -> [InBodyField: Double] {
        stored.merging(writing) { _, written in written }
    }
}

/// The twelve numbers the scale reports, the one the tape does, and the six
/// masses derived from them.
///
/// ── WHAT W3 CHANGED, AND WHY ────────────────────────────────────────────────
/// The form opened onto two buttons. "Fill from last time" and "Fill from Apple
/// Health" were a footer, a disabled state and three sentences of copy spent
/// asking a question with one sensible answer — a weigh-in is a small correction
/// to the last one, so the last one is the right starting point every time. Both
/// buttons are gone and the fields arrive full: the previous reading underneath,
/// Apple Health over the top of it where Health has something (weight, BMI and
/// body fat, and only those). Fine-tuning is typing over a filled field.
///
/// ── THE TRAP THAT SHAPED THE STATE ──────────────────────────────────────────
/// Save is gated on there being something to write. If the pre-fill had been
/// written into the edit buffer, every field would differ from what the DAY
/// holds the instant the sheet opened, Save would be live before the user
/// touched anything, and an opened-and-dismissed sheet would commit a duplicate
/// reading dated today. So the seed is a SEPARATE layer: `draft` is what the day
/// holds plus what the user typed, `seed` is only what the sheet offered, and
/// `pending` — the save gate — counts the seed only on a day that has no reading
/// of its own to duplicate.
///
/// ── AND WHY FOUR ACCORDIONS AND A HERO ──────────────────────────────────────
/// Eleven fields in three open groups plus a closed disclosure is a form you
/// scroll to read and scroll back to check. The hero answers the question the
/// sheet is opened to ask — what is the body fat, what does it weigh, how much
/// of that is muscle, and which way did each move — and the four groups below it
/// are the scale's own registers, each collapsible and each saying how many of
/// its fields are filled while it is shut. The derived masses are no longer a
/// section of their own: each one now sits in the group it belongs to, one row
/// under the percentage it was computed from.
///
/// ── THE THREE RULES THAT DID NOT CHANGE ─────────────────────────────────────
/// Derived masses are SHOWN, never entered — weight × % is the one place the
/// app does arithmetic on a body, and it does it in front of the user. Blank
/// stays blank: a reading the scale did not give is not zero, and clearing a
/// field is not an instruction to clear the column. And nothing is written
/// until Save.
struct InBodyEntryView: View {
    let model: DayModel
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    /// What the DAY holds, plus what the user has typed. Never the pre-fill.
    @State private var draft: [InBodyField: Double] = [:]
    /// What the sheet OFFERED, and where it came from. A field is read from
    /// here only while `draft` has nothing for it — see `value(_:)`.
    @State private var seed: [InBodyField: Seeded] = [:]
    /// Fields the user has actually operated. A cleared field must stay clear,
    /// and without this the seed would flow straight back into it.
    @State private var touched: Set<InBodyField> = []
    @State private var last: DailyLogRow?
    /// What Apple Health holds, once asked. Empty until the read lands, and
    /// empty forever on a device that has never been given permission.
    @State private var health = HealthBodyReading()
    /// Injected so the shot harness can photograph the Health captions without
    /// a HealthKit query, which on a simulator returns nothing, every time.
    var healthReading: (@Sendable () async -> HealthBodyReading)?
    /// Mass and Composition open, the other two shut. The first two hold the
    /// three figures the hero is drawn from, so the screen opens onto the
    /// fields most likely to need a correction.
    @State private var open: Set<FieldGroup> = [.mass, .composition]
    @FocusState private var focus: InBodyField?

    /// Three fields across a 393 pt phone, one at AX5. `@ScaledMetric` is what
    /// makes the second half true without a type-size breakpoint: the minimum
    /// grows with the text and `adaptive` fits what it can.
    @ScaledMetric(relativeTo: .body) private var cellMin: CGFloat = 104

    /// Where a filled field's number came from. It is the caption under the
    /// field — `OnyxFieldCell` already reserves that line, so it costs no
    /// layout — and it is the only thing that tells a pre-filled form apart
    /// from one the athlete typed.
    enum Source: String { case health = "Health", last = "Last" }

    private struct Seeded {
        let source: Source
        let value: Double
    }

    /// The scale's own four registers. What you weigh, what it is made of,
    /// what is water, and the mineral and the rates.
    private enum FieldGroup: String, CaseIterable, Identifiable {
        case mass, composition, water, minerals
        var id: String { rawValue }

        var title: String {
            switch self {
            case .mass:        "Mass"
            case .composition: "Composition"
            case .water:       "Water & protein"
            case .minerals:    "Minerals & derived"
            }
        }
    }

    private struct Spec {
        let field: InBodyField
        let group: FieldGroup
        let label: String
        let unit: String?
        let fraction: Int
        let range: ClosedRange<Double>
        let key: WritableKeyPath<DailyLogRow, Double?> & Sendable
    }

    private static let specs: [Spec] = [
        Spec(field: .weight, group: .mass, label: "Weight", unit: "kg", fraction: 1, range: 0...300, key: \.weightKg),
        // The one tape measurement in the app, and the reason three "no tape
        // measurements, ever" comments were struck on 2026-09-17. It sits in
        // Mass because that is what it measures a change in — not beside the
        // W:H ratio, which is a figure the SCALE reports and is never
        // recomputed from this.
        Spec(field: .waist, group: .mass, label: "Waist", unit: "cm", fraction: 1, range: 0...250, key: \.waistCm),
        Spec(field: .bodyFat, group: .composition, label: "Body fat", unit: "%", fraction: 1, range: 0...70, key: \.bodyFatPct),
        Spec(field: .muscle, group: .composition, label: "Muscle", unit: "%", fraction: 1, range: 0...100, key: \.musclePercent),
        Spec(field: .skeletal, group: .composition, label: "Skeletal muscle", unit: "kg", fraction: 1, range: 0...100, key: \.skeletalMuscleMassKg),
        Spec(field: .visceral, group: .composition, label: "Visceral fat", unit: nil, fraction: 0, range: 0...60, key: \.visceralFat),
        Spec(field: .water, group: .water, label: "Water", unit: "%", fraction: 1, range: 0...100, key: \.waterPercent),
        Spec(field: .protein, group: .water, label: "Protein", unit: "%", fraction: 1, range: 0...50, key: \.proteinPercent),
        Spec(field: .bone, group: .minerals, label: "Bone mineral", unit: "%", fraction: 2, range: 0...20, key: \.boneMineral),
        Spec(field: .bmi, group: .minerals, label: "BMI", unit: nil, fraction: 1, range: 0...80, key: \.bmi),
        Spec(field: .bmr, group: .minerals, label: "BMR", unit: "kcal", fraction: 0, range: 0...5000, key: \.bmr),
        Spec(field: .whr, group: .minerals, label: "W:H ratio", unit: nil, fraction: 2, range: 0...2, key: \.estimatedWaistToHipRatio),
    ]

    private static func specs(in group: FieldGroup) -> [Spec] { specs.filter { $0.group == group } }

    private func stored(_ spec: Spec) -> Double? { model.log?[keyPath: spec.key] }

    // MARK: The two layers

    /// What a field SHOWS: the day's own value or what the user typed, and only
    /// failing both, what the sheet offered. `touched` is what makes clearing a
    /// pre-filled field stick — without it the seed flows straight back in and
    /// the field cannot be emptied.
    private func value(_ field: InBodyField) -> Double? {
        if touched.contains(field) { return draft[field] }
        return draft[field] ?? seed[field]?.value
    }

    private func value(_ spec: Spec) -> Double? { value(spec.field) }

    /// A value as this field can actually SHOW it — `OnyxNumberField`'s own
    /// precision, applied here so the two layers can be compared on the terms
    /// the user sees rather than on the terms the store holds.
    private func shown(_ value: Double?, _ spec: Spec) -> Double? {
        guard let value else { return nil }
        let scale = pow(10.0, Double(spec.fraction))
        return (value * scale).rounded() / scale
    }

    /// `Health` / `Last` / `You` — the one line under each field.
    ///
    /// "You" covers both the value typed a moment ago and the one saved earlier
    /// today, and that is not a conflation: both are this day's own reading,
    /// which is exactly what the caption is there to distinguish from a number
    /// carried in from somewhere else.
    private func provenance(_ spec: Spec) -> String? {
        if draft[spec.field] != nil { return "You" }
        if touched.contains(spec.field) { return nil }
        return seed[spec.field]?.source.rawValue
    }

    /// Exactly what Save would write.
    private var pending: [Spec] {
        let fields = InBodySaveGate.pendingFields(
            all: Self.specs.map(\.field),
            stored: storedByField,
            draft: draft,
            seeded: Set(seed.keys),
            touched: touched
        )
        return Self.specs.filter { fields.contains($0.field) }
    }

    private var storedByField: [InBodyField: Double] {
        var out: [InBodyField: Double] = [:]
        for spec in Self.specs { out[spec.field] = stored(spec) }
        return out
    }

    /// What the masses are worth given what is ON SCREEN — the seed included.
    /// This is what the read-only rows draw, because a sheet showing a body fat
    /// of 18.0 and a blank fat mass beside it is arithmetic the user can do and
    /// the app has refused to.
    private var derived: BodyCompDerived {
        BodyComposition.derive(BodyCompInput(
            weightKg: value(.weight), bodyFatPct: value(.bodyFat), musclePercent: value(.muscle),
            waterPercent: value(.water), boneMineral: value(.bone), proteinPercent: value(.protein)
        ))
    }

    /// What the masses will be worth AFTER this save — and the only version
    /// that is ever written.
    ///
    /// ── WHY THE TWO CANNOT BE THE SAME FUNCTION ─────────────────────────────
    /// `derived` reads `value(_:)`, which falls through to the seed. Writing
    /// the masses from that was a real defect: on a day already holding a
    /// weight and nothing else, correcting the WAIST and pressing Save would
    /// have written six mass columns computed from LAST WEEK's percentages,
    /// while the percentage columns themselves stayed null — a fabricated
    /// composition point that Body trends and the widget faces would then draw,
    /// with nothing behind it. A mass may only be derived from a figure that is
    /// itself being written, or that the day already holds.
    ///
    /// `BodyComposition.derive` returns nil for a missing input, so the gating
    /// is the input set and there are no per-mass conditionals to keep in step.
    private var derivedForSave: BodyCompDerived {
        var writing: [InBodyField: Double] = [:]
        for spec in pending { writing[spec.field] = value(spec) }
        let inputs = InBodySaveGate.massInputs(stored: storedByField, writing: writing)
        return BodyComposition.derive(BodyCompInput(
            weightKg: inputs[.weight], bodyFatPct: inputs[.bodyFat],
            musclePercent: inputs[.muscle], waterPercent: inputs[.water],
            boneMineral: inputs[.bone], proteinPercent: inputs[.protein]
        ))
    }

    /// The read-only masses, in the group each was computed inside.
    private func masses(in group: FieldGroup) -> [(label: String, value: Double?)] {
        let d = derived
        switch group {
        case .mass:        return [("Fat mass", d.fatMassKg), ("Fat-free mass", d.fatFreeMassKg)]
        case .composition: return []
        case .water:       return [("Water mass", d.waterMassKg), ("Protein mass", d.proteinMassKg)]
        case .minerals:    return [("Bone mineral mass", d.boneMineralKg), ("Lean soft tissue", d.muscleMassKg)]
        }
    }

    var body: some View {
        // `.large` alone: a hero and four groups do not fit a medium detent,
        // and a form that opens half-height is a form whose first act is a drag.
        DaySheet("InBody reading", domain: .body, glass: false, detents: [.large],
                 primary: ("Save", !pending.isEmpty, save)) {
            Form {
                Section {
                    hero
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                ForEach(FieldGroup.allCases) { group in
                    Section { accordion(group) }
                }

                Section {
                    Text("Filled from your last reading, and from Apple Health where it has one. Type over anything that changed. Blank stays blank — a reading the scale did not give is not zero. Skeletal muscle and the W:H ratio are the scale's own figures; neither can be derived.")
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textSecondary)
                }
            }
            .toolbar { OnyxKeyboardDone { focus = nil } }
        }
        .onAppear {
            for spec in Self.specs { draft[spec.field] = stored(spec) }
            // `try?` on purpose: a day with no earlier reading — the first
            // weigh-in ever, or a store that has not finished pulling — is not
            // an error, it is a form with nothing to offer. Every field below
            // draws blank in that case.
            last = try? model.latestBodyReading()
            seedFromLast()
        }
        // A separate `.task` from the `onAppear` above: the stored reading is a
        // synchronous local read and must not wait behind a HealthKit query
        // that can take a second and can hang on a permission sheet. Health
        // lands SECOND and overlays what `last` seeded, for the three fields it
        // can answer — a sample measured today beats a number from last week.
        .task {
            if let healthReading { health = await healthReading() }
            else { health = await environment.latestHealthBody() }
            seedFromHealth()
        }
    }

    // MARK: The hero

    /// What the sheet was opened to find out, before any field is read.
    ///
    /// Body fat is the headline because it is the figure the plan is steered by
    /// and the one nobody can estimate; weight and skeletal muscle qualify it —
    /// the same three the Scale row prints, in the order that row prints them.
    /// Every one carries its move against the previous reading, because a body
    /// composition number alone is almost meaningless and the delta is the whole
    /// reason to weigh twice.
    private var hero: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.m) {
            HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
                Text(DayFormat.number(value(.bodyFat), fraction: 1))
                    .onyxHero()
                Text("% fat")
                    .onyxCaption()
                Spacer(minLength: OnyxSpace.s)
                // Down is the good direction for fat, and the verdict belongs
                // to the metric rather than to the sign.
                delta(.bodyFat, last?.bodyFatPct, fraction: 1, unit: "%", upIsGood: false)
            }

            // The same collapse `WeekHeroCard` makes, and deliberately NOT
            // `ViewThatFits`: both satellites carry `.frame(maxWidth: .infinity)`,
            // which tells `ViewThatFits` the row fits any width, so it would take
            // the first candidate at every size and the stacked branch would be
            // dead code.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: OnyxSpace.m) { satellites }
            } else {
                HStack(alignment: .top, spacing: OnyxSpace.m) { satellites }
            }
        }
        .padding(OnyxSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [OnyxDomain.body.start.opacity(0.32), OnyxDomain.body.end.opacity(0.08)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .onyxGlass(.tile)
        .padding(.vertical, OnyxSpace.s)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var satellites: some View {
        satellite("Weight", .weight, last?.weightKg, unit: "kg", fraction: 1, upIsGood: true)
        satellite("Skeletal muscle", .skeletal, last?.skeletalMuscleMassKg, unit: "kg", fraction: 1, upIsGood: true)
    }

    private func satellite(
        _ label: String, _ field: InBodyField, _ then: Double?,
        unit: String, fraction: Int, upIsGood: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // TWO lines, not one. "SKELETAL MUSCLE" is a register label —
            // uppercase and tracked out — and at AX5 it is wider than a 393 pt
            // phone even with the whole row to itself, so `.lineLimit(1)`
            // truncated it to "SKELETAL MUSC…". A satellite whose label has
            // been cut in half does not say which mass it is holding.
            Text(label).onyxMicro().lineLimit(2).minimumScaleFactor(0.8)
            Text(DayFormat.number(value(field), fraction: fraction, unit: unit))
                .onyxType(.display).onyxNumeral()
            delta(field, then, fraction: fraction, unit: unit, upIsGood: upIsGood)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A ▲/▼ against the previous reading.
    ///
    /// ── AND WHY IT IS BLANK ON A SHEET NOBODY HAS TYPED IN ──────────────────
    /// Only for a figure THIS DAY owns — saved earlier or typed a moment ago.
    /// A pre-filled field holds the previous reading itself, so a delta drawn
    /// against it would read "level" by construction: three chips at the top of
    /// an untouched form, each announcing that a weigh-in which has not happened
    /// yet has changed nothing. They appear, live, as the numbers are typed —
    /// which is the moment the comparison starts meaning something.
    ///
    /// OnyxUI's `DeltaChip` is the widget faces' version and sets its type in
    /// POINTS, as WidgetKit does — at AX5 on a phone sheet it is a 10 pt chip
    /// beside a 40 pt numeral. This one scales.
    @ViewBuilder
    private func delta(_ field: InBodyField, _ then: Double?, fraction: Int, unit: String, upIsGood: Bool) -> some View {
        let mine = draft[field] != nil || touched.contains(field)
        if let now = mine ? value(field) : nil, let then {
            let move = now - then
            let moved = abs(move) >= pow(0.1, Double(fraction)) / 2
            let sign = move > 0 ? "+" : "−"
            HStack(spacing: 2) {
                if moved {
                    Image(systemName: move > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.caption2)
                }
                Text(moved
                     ? "\(sign)\(DayFormat.number(abs(move), fraction: fraction, unit: unit))"
                     : "level")
                    .onyxType(.micro).onyxNumeral()
            }
            .foregroundStyle(
                !moved ? Color.onyx.textSecondary
                       : ((move > 0) == upIsGood ? Color.onyx.good : Color.onyx.danger)
            )
        } else if mine, then == nil {
            // No comparison is not "no change". Saying so costs four characters.
            Text("new").onyxType(.micro).foregroundStyle(Color.onyx.textTertiary)
        } else if !typeSize.isAccessibilitySize {
            // A reserved line, so that two satellites SIDE BY SIDE stay the
            // same height whether or not either has a comparison to draw.
            // Stacked, there is no second column to line up with and the
            // reserve is a blank micro line — 22 pt at AX5 — sitting in the
            // middle of the card for nothing.
            Text(" ").onyxType(.micro).accessibilityHidden(true)
        }
    }

    // MARK: The four groups

    private func accordion(_ group: FieldGroup) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { open.contains(group) },
                set: { isOpen in
                    if isOpen { open.insert(group) } else { open.remove(group) }
                }
            )
        ) {
            grid(group)
            ForEach(masses(in: group), id: \.label) { mass in
                // One decimal, not the control's default none: fat mass moves
                // by three or four hundred grams between readings, and a mass
                // rounded to the kilogram cannot show that at all.
                OnyxHeldRow(label: mass.label, value: mass.value, unit: "kg", fraction: 1)
            }
        } label: {
            HStack(spacing: OnyxSpace.s) {
                Text(group.title)
                Spacer(minLength: OnyxSpace.s)
                // What a SHUT group still says. A collapsed register that gave
                // no account of itself would make the user open all four to
                // find the one field the scale did not report.
                Text(filledSummary(group))
                    .onyxType(.caption).onyxNumeral()
                    .foregroundStyle(Color.onyx.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func filledSummary(_ group: FieldGroup) -> String {
        let specs = Self.specs(in: group)
        let have = specs.filter { value($0) != nil }.count
        return "\(have) of \(specs.count)"
    }

    private func grid(_ group: FieldGroup) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: cellMin), spacing: OnyxSpace.m, alignment: .leading)],
            alignment: .leading,
            spacing: OnyxSpace.s
        ) {
            ForEach(Self.specs(in: group), id: \.field) { spec in
                OnyxFieldCell(
                    label: spec.label,
                    hint: provenance(spec),
                    value: Binding(
                        get: { value(spec) },
                        // ── THE ECHO GUARD ──────────────────────────────────
                        // `OnyxNumberField` formats its text `onAppear` and its
                        // `onChange(of: text)` writes the parsed result straight
                        // back through this binding. For its other eleven
                        // callers that is a no-op — their binding IS the source
                        // of truth. Here it is not: an unguarded write would
                        // move every SEEDED value into `draft` on the first
                        // frame, which is precisely the two-layers-collapsed-
                        // into-one state this screen is built to avoid. It
                        // captioned a carried-forward number "You" and would
                        // have made the save gate depend on a render.
                        //
                        // ── AND WHY THE COMPARISON IS ROUNDED ───────────────
                        // The echo is not the value — it is the value put
                        // through the field's OWN precision and parsed back.
                        // `OnyxNumberField.format` uses
                        // `.fractionLength(0...fractionLength)`, so a weight of
                        // 64.8347 (which is what `DailyLogIngest` writes
                        // straight off HealthKit) renders "64.8" and echoes
                        // back 64.8. A plain `!=` sees a difference, calls it
                        // an edit, and arms Save on a sheet nobody touched.
                        //
                        // So both sides go through the same rounding the field
                        // does. A change the field cannot even display is not
                        // a change the user made.
                        set: { new in
                            guard shown(new, spec) != shown(value(spec), spec) else { return }
                            draft[spec.field] = new
                            touched.insert(spec.field)
                        }
                    ),
                    field: spec.field, focus: $focus,
                    unit: spec.unit, range: spec.range, fractionLength: spec.fraction
                )
            }
        }
        .padding(.vertical, OnyxSpace.xs)
    }

    // MARK: The seed

    /// The previous reading, into every field this day has nothing for.
    private func seedFromLast() {
        guard let last else { return }
        for spec in Self.specs where draft[spec.field] == nil {
            if let carried = last[keyPath: spec.key] {
                seed[spec.field] = Seeded(source: .last, value: carried)
            }
        }
    }

    /// Apple Health, over the top of it — and only where the field is still
    /// empty of the DAY's own value.
    ///
    /// Health offers weight, BMI and body fat, and nothing else. Body fat lands
    /// as a PERCENTAGE and fat-free mass is deliberately absent: `leanBodyMass`
    /// is fat-free mass, and this form's only mass field is SKELETAL MUSCLE,
    /// which is a smaller and different quantity. `DailyLogIngest` refuses the
    /// same conflation, and this must not be the one place that makes it.
    private func seedFromHealth() {
        func offer(_ field: InBodyField, _ value: Double?) {
            guard let value, draft[field] == nil, !touched.contains(field) else { return }
            seed[field] = Seeded(source: .health, value: (value * 10).rounded() / 10)
        }
        offer(.weight, health.weightKg)
        offer(.bmi, health.bmi)
        offer(.bodyFat, health.bodyFatPct)
    }

    // MARK: The one write

    private func save() {
        let patch = pending.compactMap { spec in value(spec).map { (spec.key, $0) } }
        let masses = derivedForSave
        let landed = model.saveBody { row in
            for (key, value) in patch { row[keyPath: key] = value }
            if let v = masses.fatMassKg { row.fatMassKg = v }
            if let v = masses.fatFreeMassKg { row.fatFreeMassKg = v }
            if let v = masses.muscleMassKg { row.muscleMassKg = v }
            if let v = masses.waterMassKg { row.waterMassKg = v }
            if let v = masses.boneMineralKg { row.boneMineralKg = v }
            if let v = masses.proteinMassKg { row.proteinMassKg = v }
        }
        // The weigh-in question is answered by a save landing, and by nothing
        // else — see `AppEnvironment.weighInPending`. It is deliberately not
        // conditional on WHAT was saved: an athlete who opened this form and
        // committed a reading has dealt with the banner, whether or not their
        // scale happens to report the two columns it watches.
        if landed {
            environment.answerWeighIn()
            dismiss()
        }
    }
}
