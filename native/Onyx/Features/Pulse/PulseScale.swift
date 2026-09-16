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

/// The eleven numbers the scale reports, and the five masses derived from them.
///
/// ── WHAT W11 CHANGED, AND WHY ───────────────────────────────────────────────
/// It was one flat section of eleven `LabeledContent` rows, followed by five
/// more for the derived masses — 484 pt of form for a reading taken twice a
/// week, most of it whitespace between a two-word label on the left and a
/// four-character number on the right, and no signal at all that "Muscle" and
/// "Skeletal muscle" are two different measurements of the same thing.
///
/// The scale reports the eleven in three groups that belong together, so the
/// form does too: what you weigh, what is muscle, what is water and mineral.
/// Three fields fit across a phone at the shipping type size and the grid
/// collapses to one column at the accessibility sizes (`OnyxFieldCell`).
///
/// ── THE THREE RULES THAT DID NOT CHANGE ─────────────────────────────────────
/// Derived masses are SHOWN, never entered — weight × % is the one place the
/// app does arithmetic on a body, and it does it in front of the user. Blank
/// stays blank: a reading the scale did not give is not zero. And nothing is
/// written until Save.
///
/// The derived five are now behind a disclosure, closed: they are an ANSWER,
/// and an answer that occupies a third of the form you are still filling in is
/// five rows of em dashes for as long as it takes to type the first percentage.
struct InBodyEntryView: View {
    let model: DayModel
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var draft: [Field: Double] = [:]
    @State private var last: DailyLogRow?
    /// What Apple Health holds, once asked. Empty until the read lands, and
    /// empty forever on a device that has never been given permission — which
    /// is why the button below it is hidden rather than disabled in that case:
    /// a permanently dead control teaches nothing.
    @State private var health = HealthBodyReading()
    /// Injected so the shot harness can photograph the Health row without a
    /// HealthKit query, which on a simulator returns nothing, every time.
    var healthReading: (@Sendable () async -> HealthBodyReading)?
    @State private var showDerived = false
    @FocusState private var focus: Field?

    /// Three fields across a 393 pt phone, one at AX5. `@ScaledMetric` is what
    /// makes the second half true without a type-size breakpoint: the minimum
    /// grows with the text and `adaptive` fits what it can.
    @ScaledMetric(relativeTo: .body) private var cellMin: CGFloat = 104

    enum Field: Hashable, CaseIterable {
        case weight, bmi, bodyFat, muscle, water, protein, bone, visceral, bmr, skeletal, whr
    }

    /// What the scale is measuring. The names are the plan's (§W11: "Weight &
    /// Fat · Muscle · Water"); every field it reports lands under the one it
    /// belongs to, and the odds and ends — the metabolic rate, the ratio — sit
    /// with water rather than in a fourth group of two.
    private enum FieldGroup: String, CaseIterable, Identifiable {
        case weightFat, muscle, water
        var id: String { rawValue }

        var title: String {
            switch self {
            case .weightFat: "Weight & fat"
            case .muscle:    "Muscle"
            case .water:     "Water & the rest"
            }
        }
    }

    private struct Spec {
        let field: Field
        let group: FieldGroup
        let label: String
        let unit: String?
        let fraction: Int
        let range: ClosedRange<Double>
        let key: WritableKeyPath<DailyLogRow, Double?> & Sendable
    }

    private static let specs: [Spec] = [
        Spec(field: .weight, group: .weightFat, label: "Weight", unit: "kg", fraction: 1, range: 0...300, key: \.weightKg),
        Spec(field: .bodyFat, group: .weightFat, label: "Body fat", unit: "%", fraction: 1, range: 0...70, key: \.bodyFatPct),
        Spec(field: .bmi, group: .weightFat, label: "BMI", unit: nil, fraction: 1, range: 0...80, key: \.bmi),
        Spec(field: .visceral, group: .weightFat, label: "Visceral fat", unit: nil, fraction: 0, range: 0...60, key: \.visceralFat),
        Spec(field: .muscle, group: .muscle, label: "Muscle", unit: "%", fraction: 1, range: 0...100, key: \.musclePercent),
        Spec(field: .skeletal, group: .muscle, label: "Skeletal muscle", unit: "kg", fraction: 1, range: 0...100, key: \.skeletalMuscleMassKg),
        Spec(field: .protein, group: .muscle, label: "Protein", unit: "%", fraction: 1, range: 0...50, key: \.proteinPercent),
        Spec(field: .water, group: .water, label: "Water", unit: "%", fraction: 1, range: 0...100, key: \.waterPercent),
        Spec(field: .bone, group: .water, label: "Bone mineral", unit: "%", fraction: 2, range: 0...20, key: \.boneMineral),
        Spec(field: .bmr, group: .water, label: "BMR", unit: "kcal", fraction: 0, range: 0...5000, key: \.bmr),
        Spec(field: .whr, group: .water, label: "W:H ratio", unit: nil, fraction: 2, range: 0...2, key: \.estimatedWaistToHipRatio),
    ]

    private static func specs(in group: FieldGroup) -> [Spec] { specs.filter { $0.group == group } }

    private func stored(_ spec: Spec) -> Double? { model.log?[keyPath: spec.key] }

    /// The one reserved line under each field.
    ///
    /// ── A PERCENTAGE OF A BODY IS NOT A QUANTITY ANYONE FEELS ───────────────
    /// "Body fat 18.4" and "Muscle 44.1" are the numbers the scale prints and
    /// they are almost impossible to reason about against each other: 18 % of
    /// what, and is 44 % muscle a lot? The kilograms are the figure a person
    /// actually tracks, and the sheet already computes all five of them — it
    /// just kept them folded inside a closed disclosure at the bottom.
    ///
    /// So a percentage field shows its OWN mass live, the moment there is a
    /// weight to multiply by, and falls back to the previous reading when there
    /// is not. The derived section below stays: it is the same five figures
    /// assembled as a set, which is a different question from "what is this
    /// field worth".
    private func hint(_ spec: Spec) -> String? {
        if spec.unit == "%",
           let mass = BodyComposition.massFromPct(draft[.weight], draft[spec.field]) {
            return "= \(DayFormat.number(mass, fraction: 1)) kg"
        }
        return carried(spec).map { "last \(DayFormat.number($0, fraction: spec.fraction))" }
    }

    /// The previous reading, offered only while this day has none of its own.
    private func carried(_ spec: Spec) -> Double? {
        draft[spec.field] == nil ? last?[keyPath: spec.key] : nil
    }

    private var edits: [Spec] {
        Self.specs.filter { draft[$0.field] != nil && draft[$0.field] != stored($0) }
    }

    private var fillable: [Spec] { Self.specs.filter { carried($0) != nil } }

    private var derived: BodyCompDerived {
        BodyComposition.derive(BodyCompInput(
            weightKg: draft[.weight], bodyFatPct: draft[.bodyFat], musclePercent: draft[.muscle],
            waterPercent: draft[.water], boneMineral: draft[.bone], proteinPercent: draft[.protein]
        ))
    }

    var body: some View {
        // `.large` alone: eleven fields in three groups and a disclosure do
        // not fit a medium detent, and a form that opens half-height is a form
        // whose first act is a drag.
        DaySheet("InBody reading", domain: .body, glass: false, detents: [.large],
                 primary: ("Save", !edits.isEmpty, save)) {
            Form {
                fillSection
                ForEach(FieldGroup.allCases) { group in
                    Section {
                        grid(group)
                    } header: {
                        OnyxSectionHeader(group.title, .body)
                    }
                }
                Section {
                    Text("Blank stays blank — a reading the scale did not give is not zero. Skeletal muscle and the W:H ratio are the scale's own figures; neither can be derived.")
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textSecondary)
                }
                derivedSection
            }
            .toolbar { OnyxKeyboardDone { focus = nil } }
        }
        .onAppear {
            for spec in Self.specs { draft[spec.field] = stored(spec) }
            // `try?` on purpose: a day with no earlier reading — the first
            // weigh-in ever, or a store that has not finished pulling — is not
            // an error, it is a form with nothing to offer. Everything below
            // reads `last` as an optional and draws the plain form when it is
            // nil, which is why "Fill from last time" can be disabled rather
            // than dangerous.
            last = try? model.latestBodyReading()
        }
        // A separate `.task` from the `onAppear` above: the stored reading is a
        // synchronous local read and must not wait behind a HealthKit query
        // that can take a second and can hang on a permission sheet.
        .task {
            if let healthReading { health = await healthReading() }
            else { health = await environment.latestHealthBody() }
        }
    }

    // MARK: The fields

    private func grid(_ group: FieldGroup) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: cellMin), spacing: OnyxSpace.m, alignment: .leading)],
            alignment: .leading,
            spacing: OnyxSpace.s
        ) {
            ForEach(Self.specs(in: group), id: \.field) { spec in
                OnyxFieldCell(
                    label: spec.label,
                    hint: hint(spec),
                    value: Binding(get: { draft[spec.field] }, set: { draft[spec.field] = $0 }),
                    field: spec.field, focus: $focus,
                    unit: spec.unit, range: spec.range, fractionLength: spec.fraction
                )
            }
        }
        .padding(.vertical, OnyxSpace.xs)
    }

    // MARK: Fill from last time

    /// One button, always present once there is a form to fill.
    ///
    /// Disabled rather than hidden when there is nothing to fill: a control
    /// that appears and disappears with the store is a control the user cannot
    /// learn, and the two cases it is absent for — no earlier reading at all,
    /// and every field already typed — are worth stating rather than
    /// disappearing. `last` is optional the whole way down, so the nil case is
    /// a disabled button and a sentence, never a crash.
    @ViewBuilder
    private var fillSection: some View {
        Section {
            Button {
                for spec in fillable { draft[spec.field] = last?[keyPath: spec.key] }
            } label: {
                Label("Fill from last time", systemImage: "clock.arrow.circlepath")
            }
            .disabled(fillable.isEmpty)
            .accessibilityHint("Fills the empty fields only. Nothing is saved until you press Save.")

            // Hidden, not disabled, when Health has nothing — unlike the button
            // above it, whose empty case ("no earlier reading") is a state the
            // user will grow out of within a week. A device that has never been
            // granted Health access will never fill this one, and a control
            // that can never work is worse than no control.
            if !health.isEmpty {
                Button {
                    for (field, value) in healthFillable { draft[field] = value }
                } label: {
                    Label("Fill from Apple Health", systemImage: "heart.text.square")
                }
                .disabled(healthFillable.isEmpty)
                .accessibilityHint("Fills the empty fields only. Nothing is saved until you press Save.")
            }
        } footer: {
            Text(fillFooter)
        }
    }

    /// What Health can offer that the form does not already have.
    ///
    /// Empty fields only, exactly like "Fill from last time": a scale reading
    /// the person has just typed is better evidence than a Health sample from
    /// some other device, and silently replacing it is the one thing a prefill
    /// must never do.
    ///
    /// Body fat lands as a PERCENTAGE and fat-free mass is deliberately absent:
    /// `leanBodyMass` is fat-free mass, and this form's only mass field is
    /// SKELETAL MUSCLE, which is a smaller and different quantity.
    /// `DailyLogIngest` refuses the same conflation, and this must not be the
    /// one place that makes it.
    private var healthFillable: [(Field, Double)] {
        var out: [(Field, Double)] = []
        func offer(_ field: Field, _ value: Double?) {
            guard let value, draft[field] == nil else { return }
            out.append((field, (value * 10).rounded() / 10))
        }
        offer(.weight, health.weightKg)
        offer(.bmi, health.bmi)
        offer(.bodyFat, health.bodyFatPct)
        return out
    }

    private var fillFooter: String {
        guard let lastDate = last?.date else {
            return health.isEmpty
                ? "No earlier reading on this device yet — the first weigh-in has nothing to copy from."
                : "No earlier reading on this device yet. Apple Health has your latest weigh-in."
        }
        if fillable.isEmpty {
            return "Every field already has a value. The last reading was \(Swap.shortDayLabel(lastDate))."
        }
        return "Copies \(fillable.count) empty \(fillable.count == 1 ? "field" : "fields") from \(Swap.shortDayLabel(lastDate)). Nothing is saved until you press Save."
    }

    // MARK: The derived five

    private var derivedSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showDerived) {
                derivedRow("Lean soft tissue", derived.muscleMassKg)
                derivedRow("Fat mass", derived.fatMassKg)
                derivedRow("Water mass", derived.waterMassKg)
                derivedRow("Protein mass", derived.proteinMassKg)
                derivedRow("Fat-free mass", derived.fatFreeMassKg)
            } label: {
                HStack(spacing: OnyxSpace.s) {
                    Text("Composition")
                    Spacer(minLength: OnyxSpace.s)
                    Text(derivedSummary)
                        .onyxType(.caption).onyxNumeral()
                        .foregroundStyle(Color.onyx.textSecondary)
                        .lineLimit(1)
                }
            }
        } footer: {
            Text("Weight × percentage, computed as you type and saved with the reading. Lean soft tissue is not skeletal muscle.")
        }
    }

    /// What the closed disclosure says. The count, not a figure: five masses do
    /// not have one headline between them, and "50.3 kg" beside the word
    /// "Composition" would read as the whole answer.
    private var derivedSummary: String {
        let masses = derived
        let have = [masses.muscleMassKg, masses.fatMassKg, masses.waterMassKg, masses.proteinMassKg, masses.fatFreeMassKg]
            .compactMap { $0 }.count
        return have == 0 ? "—" : "\(have) of 5"
    }

    private func derivedRow(_ label: String, _ value: Double?) -> some View {
        OnyxHeldRow(label: label, value: value, unit: "kg")
    }

    private func save() {
        let patch = edits.compactMap { spec in draft[spec.field].map { (spec.key, $0) } }
        let masses = derived
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
