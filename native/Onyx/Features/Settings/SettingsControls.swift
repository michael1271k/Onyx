import SwiftUI
import OnyxUI

/// The two things every screen in this tab needs: a number row, and a ground.
///
/// ── WHY A `Form` AND NOT A HAND-BUILT LIST OF TILES ─────────────────────────
/// §3.5 of the plan is explicit that Settings is stock: `Form`, `Toggle`,
/// `Stepper`, `Picker`, one `Section` per concern. That is not laziness about
/// the design — it is the design. A settings screen is the one place where
/// looking exactly like every other iOS settings screen IS the correct answer,
/// because the user already knows how it works, and because stock controls come
/// with Dynamic Type, VoiceOver, Switch Control and the keyboard behaviours for
/// free. The Obsidian Glass identity arrives through the ground and the section
/// accents, not by rebuilding a `Toggle`.

// MARK: - The ground

extension View {
    /// A `Form` on the app's black ground with its domain bleed.
    ///
    /// `.scrollContentBackground(.hidden)` is the whole trick: without it the
    /// form paints `systemGroupedBackground` over everything behind it and the
    /// mesh is invisible.
    func onyxFormBackground(_ domain: OnyxDomain) -> some View {
        self
            .scrollContentBackground(.hidden)
            // The rows are the app's material, not a grey. Over true black a
            // grouped row would be a flat `#1C1C1E` rectangle and the mesh
            // behind the top of the screen would stop at the first section;
            // `ultraThinMaterial` samples what is behind it, so the first tile
            // carries a trace of the domain's accent and the ones further down
            // fade to black. That gradient IS the hierarchy.
            .listRowBackground(Rectangle().fill(.ultraThinMaterial))
            .onyxScreen(domain)
            .tint(domain.accent)
    }

    /// The neutral ground — a screen that belongs to no domain (§W5.2).
    ///
    /// Settings is about all four and therefore about none: painting it Ion
    /// would say the tab is a training screen, and painting it a fifth colour
    /// would add an accent that means nothing. The mesh goes grey; the controls
    /// keep the app's own accent so a toggle still reads as Onyx's.
    func onyxFormBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .listRowBackground(Rectangle().fill(.ultraThinMaterial))
            .onyxScreen()
            .tint(OnyxDomain.train.accent)
    }
}

/// A section header in the screen's accent.
///
/// Uppercased is the platform's own convention for grouped-form headers; the
/// colour is what says which domain the section belongs to.
struct OnyxSectionHeader: View {
    let title: String
    let color: Color

    init(_ title: String, _ domain: OnyxDomain) {
        self.title = title
        self.color = domain.accent
    }

    /// A section whose colour is not a DOMAIN's — the weekly-volume form groups
    /// by muscle family, and a family's colour is its own (`Color.onyx.muscle`),
    /// not one of the four accents. Keeping it as a domain is what made every
    /// arm section indigo in the first place.
    init(_ title: String, color: Color) {
        self.title = title
        self.color = color
    }

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .tracking(12 * 0.01)
            .foregroundStyle(color)
    }
}

// MARK: - A number

/// One editable figure, or none.
///
/// ── EMPTY IS `nil`, AND `nil` IS NOT ZERO ───────────────────────────────────
/// A blank body-fat target means "I have not set one", and the placeholder is an
/// em dash to say so. Storing it as 0 would mean "my target is zero percent body
/// fat", which every downstream gauge would then draw. This is the single most
/// repeated rule in the codebase and it is enforced here rather than in each of
/// the eleven callers.
///
/// ── AND WHY THERE IS NO DEBOUNCE ────────────────────────────────────────────
/// The web version committed on blur AND on a 600 ms timer, because a controlled
/// React input has no idea when the user is finished. SwiftUI does: this commits
/// when the field loses focus. Typing "1955" therefore writes once, not four
/// times.
///
/// ── BUT THE TEXT IS PARSED ON EVERY KEYSTROKE ───────────────────────────────
/// The binding is a `String`, not `TextField(value:format:)`. That form only
/// parses when EDITING ENDS, and a back-swipe removes the view before the field
/// resigns — so the last number typed never reached the model at all, and the
/// screen you navigated away from silently discarded it. Parsing as you type
/// keeps the model current at every instant, which makes "commit whatever is
/// there" safe from anywhere, including `onDisappear`.
///
/// ── AND WHY THE FOCUS STATE IS THE CALLER'S ─────────────────────────────────
/// `.focused()` binds the field it is applied TO. A row that owned its own
/// `@FocusState` would leave the screen unable to dismiss the keyboard — and a
/// decimal pad has no return key, so "tap elsewhere" is the only other way out
/// and on a `Form` that means tapping a control you did not mean to touch. The
/// screen therefore owns one focus value for all its fields, which also gives it
/// the one moment a commit should happen: the field losing it.
/// The editable figure itself — the parse, the clamp and the commit, with no
/// opinion about where the label goes.
///
/// Extracted from `OnyxNumberRow` in W11, when the InBody form stopped being
/// eleven full-width rows and became three grids of cells. Everything below the
/// layout is the part that is hard to get right — see the four notes on
/// `OnyxNumberRow` — and a second copy of it in a cell would have been a second
/// place for a typed half-kilo to go missing.
struct OnyxNumberField<Field: Hashable>: View {
    /// VoiceOver's name for the field. The visible label is the wrapper's.
    let label: String
    @Binding var value: Double?
    let field: Field
    @FocusState.Binding var focus: Field?
    var unit: String?
    /// Clamped on commit rather than rejected — `min=0` as an HTML attribute
    /// with no code behind it is how the web version accepts a typed −5.
    var range: ClosedRange<Double> = 0...100_000
    var fractionLength: Int = 0
    var alignment: TextAlignment = .trailing
    /// An empty field is one em dash wide. A right-aligned field in a
    /// `LabeledContent` is a ~10 pt target without this.
    var width: CGFloat = 90
    /// Take exactly `width` rather than at least it.
    ///
    /// ── WHY A CELL NEEDS THIS AND A ROW DOES NOT ────────────────────────────
    /// A `TextField` is greedy: given slack in an `HStack` it takes all of it,
    /// and a `Spacer` beside it collapses to nothing. In a `LabeledContent`
    /// that is exactly right — the label is on the left and the field fills the
    /// rest. In a grid cell it puts the unit against the far edge, six
    /// characters away from the number it belongs to, reading as a column of
    /// its own. A fixed width lets the unit sit where a suffix sits.
    var fixedWidth = false
    /// Fired when this field loses focus AND its value actually changed.
    var onCommit: () -> Void = {}

    @State private var text = ""
    /// What was last sent to the model, so that focusing a field and leaving it
    /// alone writes nothing. Without it, a tap through a form queues an outbox
    /// row per field touched — and in the levers that also forces the rung to
    /// `custom`, silently cancelling a rung by looking at it.
    @State private var committed: Double??

    var body: some View {
        HStack(spacing: 6) {
            field(sized: fixedWidth)

            if let unit {
                Text(unit)
                    .foregroundStyle(Color.onyx.textTertiary)
                    // The unit is decoration beside a value VoiceOver already
                    // reads with its label; announcing "kilograms" twice is
                    // worse than not announcing it.
                    .accessibilityHidden(true)
            }
            // The cell stretches this stack so the underline spans it; the
            // field itself is fixed, so the slack lands here rather than
            // between the number and its unit.
            if fixedWidth { Spacer(minLength: 0) }
        }
        .onAppear {
            text = Self.format(value, fractionLength)
            committed = .some(value)
        }
        // A value that arrives from the store — a sync pull, or another screen —
        // is shown, but never while the field is being typed into.
        .onChange(of: value) { _, new in
            guard focus != field else { return }
            text = Self.format(new, fractionLength)
        }
        .onChange(of: focus) { old, _ in
            guard old == field else { return }
            if let v = value {
                value = min(max(v, range.lowerBound), range.upperBound)
            }
            text = Self.format(value, fractionLength)
            guard committed != .some(value) else { return }
            committed = .some(value)
            onCommit()
        }
    }

    @ViewBuilder
    private func field(sized fixed: Bool) -> some View {
        let box = TextField("—", text: $text)
            .keyboardType(fractionLength > 0 ? .decimalPad : .numberPad)
            .multilineTextAlignment(alignment)
            .focused($focus, equals: field)
            .onyxNumeral()
            .contentShape(.rect)
            .accessibilityLabel(unit == nil ? label : "\(label), \(unit!)")
            .accessibilityValue(value == nil ? "Not set" : text)
            .onChange(of: text) { _, new in value = Self.parse(new) }
        if fixed {
            box.frame(width: width, alignment: .leading)
        } else {
            box.frame(minWidth: width, alignment: alignment == .trailing ? .trailing : .leading)
        }
    }

    /// Empty is `nil`, and a comma is a decimal point. A decimal pad on a
    /// German or Hebrew keyboard emits `,` — `Double(",5")` is nil, so a typed
    /// half kilo would silently clear the field.
    private static func parse(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : Double(cleaned)
    }

    private static func format(_ value: Double?, _ fractionLength: Int) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...fractionLength)).grouping(.never))
    }
}

/// One editable figure, or none — label leading, field trailing.
///
/// ── EMPTY IS `nil`, AND `nil` IS NOT ZERO ───────────────────────────────────
/// A blank body-fat target means "I have not set one", and the placeholder is an
/// em dash to say so. Storing it as 0 would mean "my target is zero percent body
/// fat", which every downstream gauge would then draw. This is the single most
/// repeated rule in the codebase and it is enforced in `OnyxNumberField` rather
/// than in each of the eleven callers.
///
/// ── AND WHY THE FOCUS STATE IS THE CALLER'S ─────────────────────────────────
/// `.focused()` binds the field it is applied TO. A row that owned its own
/// `@FocusState` would leave the screen unable to dismiss the keyboard — and a
/// decimal pad has no return key, so "tap elsewhere" is the only other way out
/// and on a `Form` that means tapping a control you did not mean to touch. The
/// screen therefore owns one focus value for all its fields, which also gives it
/// the one moment a commit should happen: the field losing it.
struct OnyxNumberRow<Field: Hashable>: View {
    let label: String
    @Binding var value: Double?
    let field: Field
    @FocusState.Binding var focus: Field?
    var unit: String?
    var range: ClosedRange<Double> = 0...100_000
    var fractionLength: Int = 0
    var onCommit: () -> Void = {}

    var body: some View {
        LabeledContent {
            OnyxNumberField(
                label: label, value: $value, field: field, focus: $focus,
                unit: unit, range: range, fractionLength: fractionLength, onCommit: onCommit
            )
        } label: {
            Text(label)
        }
    }
}

/// The same figure as a GRID CELL: its name above it, and a hairline under it
/// so a bare number still reads as something you can type in.
///
/// ── WHY A FORM GREW A GRID ──────────────────────────────────────────────────
/// Eleven `LabeledContent` rows is 484 pt of form to enter a weigh-in, most of
/// it the whitespace between a two-word label on the left and a four-character
/// number on the right. The scale reports the eleven in three groups that
/// belong together — what you weigh, what is muscle, what is water — and three
/// fields fit across a phone at the shipping type size. §W11: two to three
/// fields a row.
///
/// At the accessibility sizes the grid's own `adaptive` minimum grows with the
/// type and the three columns become one, which is the same escape every other
/// compaction in this app takes.
struct OnyxFieldCell<Field: Hashable>: View {
    let label: String
    /// "last 65.1" — the previous reading, offered while this one is blank.
    /// Nil once the field has a value of its own; a hint under a filled field
    /// is a second number competing with the one you just typed.
    var hint: String?
    @Binding var value: Double?
    let field: Field
    @FocusState.Binding var focus: Field?
    var unit: String?
    var range: ClosedRange<Double> = 0...100_000
    var fractionLength: Int = 0

    /// Wide enough for "10000" at the shipping size, and it grows with the
    /// type — a fixed 54 pt at AX5 is a five-digit BMR in a two-digit box.
    @ScaledMetric(relativeTo: .body) private var fieldWidth: CGFloat = 54

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .onyxMicro()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            OnyxNumberField(
                label: label, value: $value, field: field, focus: $focus,
                unit: unit, range: range, fractionLength: fractionLength,
                alignment: .leading, width: fieldWidth, fixedWidth: true
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 3)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(focus == field ? Color.onyx.accent(.body) : Color.onyx.hairline)
                    .frame(height: focus == field ? 1.5 : 1)
            }
            // A reserved line, so a group where one field has history and the
            // next does not still lays out as a grid.
            Text(hint ?? " ")
                .onyxType(.micro)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(Color.onyx.textTertiary)
                .accessibilityHidden(hint == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // An empty field is one em dash wide and the cell around it is 104.
        // Tapping the label, the hint or the whitespace focuses the field —
        // otherwise three quarters of a cell that looks like a control is not
        // one.
        .contentShape(.rect)
        .onTapGesture { focus = field }
    }
}

/// A figure a rung is holding: shown, never editable.
///
/// Deliberately NOT a disabled `TextField`. A greyed-out field says "this is
/// yours and something is temporarily wrong"; a plain value says "this is the
/// rung's answer", which is the truth. The way back to editing is choosing "My
/// own numbers", and the section footer says so.
struct OnyxHeldRow: View {
    let label: String
    let value: Double?
    var unit: String?
    /// Whole by default — a rung's calorie or step goal has no decimals. The
    /// InBody sheet passes 1: a body mass moves by a few hundred grams between
    /// readings and a figure rounded to the kilogram cannot show that at all.
    var fraction: Int = 0

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Text(value.map { $0.formatted(.number.precision(.fractionLength(0...fraction))) } ?? "—")
                    .onyxNumeral()
                    .foregroundStyle(Color.onyx.textPrimary)
                if let unit {
                    Text(unit)
                        .foregroundStyle(Color.onyx.textTertiary)
                        .accessibilityHidden(true)
                }
            }
        } label: {
            Text(label)
        }
        .accessibilityLabel(unit == nil ? label : "\(label), \(unit!)")
    }
}

/// The keyboard's own Done button.
///
/// A decimal pad has no return key, so a field on one can only be committed by
/// tapping elsewhere — which on a `Form` means tapping a control the user did
/// not mean to touch.
struct OnyxKeyboardDone: ToolbarContent {
    let dismiss: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done", action: dismiss)
        }
    }
}
