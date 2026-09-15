import SwiftUI
import OnyxUI
import OnyxCore

/// One row of five words, one tap (founder decision 6).
///
/// ── ONE CONTROL, BECAUSE THERE IS ONE QUESTION ──────────────────────────────
/// Fatigue asks what the body could do and the stress log asks what is on your
/// mind, and the two answer differently on the same day — but both are a 1–5
/// self-report on the same neutral 3, and D6 folds the two into
/// ONE term of the Stress index. Two controls for that is two places for the
/// hit target, the selected state and the VoiceOver traits to drift apart —
/// and the reader would have to learn the answer shape twice on one screen.
///
/// ── WHY NOT A `Picker` ──────────────────────────────────────────────────────
/// The row this replaces was `.pickerStyle(.inline)`: five list rows, each
/// "Word — sentence", inside a section per slot. Correct, free VoiceOver, and
/// four hundred points tall for a reading taken twice a day. Decision 6 asks for
/// five equal targets and no scroll, which is a shape no `PickerStyle` has.
///
/// ── AND WHY `ViewThatFits` RATHER THAN A TYPE-SIZE BRANCH ───────────────────
/// The deciding fact is whether the longest WORD still fits a fifth of the
/// width, which is a measurement, not a size class: "Exhausted" holds the row
/// at shipping sizes and gives up around xxLarge. A hand-written
/// `isAccessibilitySize` branch would keep a broken row at xxLarge and would
/// have to be re-guessed every time a word changes.
///
/// ── AND WHY EVERY CELL CARRIES THE WHOLE VOCABULARY, INVISIBLY ──────────────
/// The first attempt truncated instead of stacking. `.frame(maxWidth:
/// .infinity)` is what makes five cells equal, and it also makes the HStack's
/// IDEAL width flexible — so `ViewThatFits` was told the row fits any width and
/// always chose it, and the words then truncated inside their equal cells
/// ("Overwh…"). A hidden `ZStack` of all five labels under the real one gives
/// every cell the same ideal — the widest word's — which is both what makes
/// them equal and what lets the measurement be believed.
///
/// ── AND WHY THAT IDEAL IS DELIBERATELY `squeeze` POINTS SHORT ───────────────
/// Measured at its true width the row NEVER fits: "Exhausted" is 66 pt of a
/// 62 pt cell on a 375 pt phone, so a strictly honest measurement stacks five
/// words that a screenshot shows fitting perfectly well. The missing fact is
/// that `Text` is allowed to compress — `minimumScaleFactor(0.9)` floors a
/// 13 pt caption at 11.7 pt, which is above this design system's 11 pt floor.
/// So the budget is stated rather than discovered: each cell may borrow
/// `squeeze` points, and `ViewThatFits` is asked whether the row fits AFTER
/// that. One step up the type scale it no longer does, and the column is what
/// you get — which is the correct answer there and was the wrong one here.
struct FiveWordPicker: View {

    /// A rung: the word you tap, and the definition VoiceOver speaks.
    struct Word: Identifiable, Equatable {
        let value: Int
        let label: String
        let hint: String
        var id: Int { value }

        init(value: Int, label: String, hint: String) {
            self.value = value
            self.label = label
            self.hint = hint
        }

        init(_ level: FatigueLevel) {
            self.init(value: level.value, label: level.label, hint: level.hint)
        }

        init(_ level: StressLevel) {
            self.init(value: level.value, label: level.label, hint: level.hint)
        }
    }

    let words: [Word]
    let selected: Int?
    let onPick: (Int) -> Void

    /// The selected cell's fill.
    ///
    /// Not a parameter: `OnyxTokens` states the rule where `fatigue` is defined
    /// — the subjective readings on this screen share severity's three-step
    /// ramp so a reader learns ONE colour language — and a hook here is an
    /// invitation for the next scale to break it.
    private var tint: (Int?) -> Color { Color.onyx.fatigue }

    /// What a cell may borrow from the word inside it before the row gives up
    /// and becomes a column, and the floor the word may compress to.
    ///
    /// ── THE TWO NUMBERS ARE ONE DECISION, AND THEY WERE MEASURED ────────────
    /// At 375 pt a `Form` section gives this row 338 pt, so a cell is 64 pt.
    /// "Exhausted" — the widest word either scale carries — is about 66 pt at
    /// the caption size, plus its padding. A budget the label cannot then honour
    /// buys a row of truncated words, which is worse than a column; a budget
    /// smaller than the compression the label IS allowed stacks five words that
    /// fit. So: 10 points borrowed, 0.88 as the floor (11.4 pt of a 13 pt
    /// caption, above this design system's 11 pt minimum), and 2 pt of side
    /// padding rather than `xs` to give the longest word the room.
    ///
    /// One step up the type scale the arithmetic stops working and the column is
    /// what you get, which is the right answer there.
    private static let squeeze: CGFloat = 10
    private static let floor: CGFloat = 0.88
    private static let sidePadding: CGFloat = 2

    /// Bumped on every tap, for the haptic. `.sensoryFeedback` needs something
    /// that CHANGES, and the selection does not when you re-tap what is already
    /// selected — which is a tap that still commits and still closes the sheet.
    @State private var taps = 0

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: OnyxSpace.xs) { cells }
            VStack(spacing: OnyxSpace.xs) { cells }
        }
        .sensoryFeedback(.selection, trigger: taps)
        .accessibilityElement(children: .contain)
    }

    private var cells: some View {
        ForEach(words) { word in
            let on = word.value == selected
            Button {
                taps += 1
                onPick(word.value)
            } label: {
                ZStack {
                    // The whole vocabulary, invisible: the cell's ideal width is
                    // the widest word's, less the compression budget above.
                    ForEach(words) { other in
                        Text(other.label)
                            .onyxType(.caption).fontWeight(.semibold)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, -Self.squeeze / 2)
                            .hidden()
                    }
                    Text(word.label)
                        .onyxType(.caption)
                        .fontWeight(on ? .semibold : .regular)
                        .foregroundStyle(on ? Color.onyx.base : Color.onyx.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(Self.floor)
                        .multilineTextAlignment(.center)
                }
                    .padding(.horizontal, Self.sidePadding)
                    // 56, not 44: five of these ARE the sheet, and a target
                    // that is only just legal reads as a list row you might
                    // have to scroll rather than as the answer.
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(background(on: on))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onyxPress(scale: 0.97)
            .accessibilityLabel(word.label)
            .accessibilityHint(word.hint)
            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        }
    }

    /// Selection moves THREE things — the fill from material to solid, the ink
    /// from primary to the ground, and the weight from regular to semibold — so
    /// it survives a reader who cannot separate the hue from its neighbour.
    @ViewBuilder
    private func background(on: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
        if on {
            shape.fill(tint(selected))
        } else {
            shape.fill(.ultraThinMaterial)
                .overlay(shape.strokeBorder(Color.onyx.hairline, lineWidth: 0.5))
        }
    }
}
