import OnyxCore
import OnyxData
import OnyxUI
import SwiftUI
import WatchKit

/// Page two of the set screen: what the set you just logged WAS, and how it
/// went (founder decision 3).
///
/// ── IT DESCRIBES THE SET BEHIND YOU, NOT THE ONE IN FRONT ───────────────────
/// Page one is the set you are ABOUT to do and it does not exist yet; a patch
/// amends a set that does. So every control here writes an `amend` against
/// `WatchModel.lastLogged` the instant it is tapped — no Save button, the same
/// grammar as the RPE ladder on the rest screen, which rates the set that
/// earned the rest. The header names the set for the same reason the phone's
/// options sheet prints the movement in its title bar: you got here with a
/// swipe, and that line is the only evidence you are describing the set you
/// meant.
///
/// ── TWO AXES, NEITHER ABLE TO EXPRESS THE OTHER ─────────────────────────────
/// "Warm-up" and "form broke" are both true of the same set. `set_type` is the
/// one and `quality` is the other, exactly as on the phone — folding technique
/// into the type would force a choice between two facts and would give every
/// consumer of "is this a working set" an opinion about form.
///
/// ── THE VOCABULARY IS `SetTags`, WHICH IS ALSO THE PHONE'S ──────────────────
/// Four kinds and six qualities, in `SetTags`' own order, with `SetTags`' own
/// words — since W3 the phone's `SetKind` and `SetQuality` read the same table
/// rather than their own copies of it. There is no "Normal" chip and no
/// "Clean" chip, because both are the ABSENCE of a claim: tapping the kind a
/// set already carries withdraws it, and a chip asserting a set was inspected
/// and passed is a claim nobody made.
///
/// ── AND WHY IT IS TWO COLUMNS AND NOT FOUR ──────────────────────────────────
/// `WatchPanel` decides, and `OnyxWatchLayoutTests` pins it: 146 pt over four
/// chips is 33 pt each, which is a row of four ellipses. The phone's own sheet
/// makes the same call at an accessibility size — "four 74 pt chips is four
/// truncated words" — and a 40 mm wrist is that case permanently.
struct SetQualityPanel: View {

    @Environment(WatchModel.self) private var model
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            header
            // ── EVERY ACTION CARRIES THE ID THIS PANEL DREW ─────────────────
            // A set logged on the PHONE can arrive between the render and the
            // finger landing; the mutators used to re-read "the last set" and
            // would have tagged the phone's. Capturing the id here makes a
            // stale tap a refusal.
            if let last = model.lastLogged {
                kinds(last)
                if isUnilateral { sides(last) }
                qualities(last)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dimmedWhenLuminanceReduced()
    }

    // MARK: - Which set

    private var header: some View {
        Text(headline)
            .font(WatchType.label)
            .foregroundStyle(WatchInk.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityAddTraits(.isHeader)
    }

    /// `Set 2 · Chest Press`. The movement second and truncating first: the
    /// ordinal is the half that disambiguates, and at 146 pt a long name would
    /// otherwise push it off.
    private var headline: String {
        guard let last = model.lastLogged else { return "Set quality" }
        guard let movement = model.lastLoggedMovement else { return "Set \(last.setIndex)" }
        // "Logged ·" because the navigation bar two rows up says "Set 3/3" —
        // the set you are ABOUT to do — and two ordinals thirty points apart
        // with nothing to tell them apart reads as a screen that is confused.
        return "Logged · Set \(last.setIndex) · \(movement.plan.name)"
    }

    private var empty: some View {
        Text("Log a set, then describe it here.")
            .font(WatchType.label)
            .foregroundStyle(WatchInk.secondary)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - What it was

    private func kinds(_ set: WorkoutSet) -> some View {
        section("What it was", hint: SetTags.hint(for: set.setType)) {
            grid(count: SetTags.tagKeys.count, floor: WatchPanel.wordChip) {
                ForEach(SetTags.tagKeys, id: \.self) { key in
                    chip(
                        glyph: SetTags.tags[key]?.label,
                        label: SetTags.word(for: key),
                        selected: set.setType == key,
                        hint: SetTags.hint(for: key)
                    ) {
                        model.setKind(key, on: set.id)
                        WKInterfaceDevice.current().play(.click)
                    }
                }
            }
        }
    }

    // MARK: - Which side

    /// Only on a movement trained one limb at a time — `Unilateral`, the same
    /// predicate that decides whether the phone offers to split a set.
    private var isUnilateral: Bool {
        Unilateral.isUnilateral(model.lastLoggedMovement?.plan.name)
    }

    /// ── TWO CHIPS, NOT THREE, AND THE LINE UNDER THEM SAYS WHY ──────────────
    /// There is no "Both". `SetPatch` reads nil as UNCHANGED and has no way to
    /// say "back to null" — deliberately, upstream: clearing a side means two
    /// rows becoming one, which is a void-and-append and not a patch. A third
    /// chip that silently did nothing would be worse than an absent one, which
    /// is the same call the phone's sheet makes about its Split button.
    private func sides(_ set: WorkoutSet) -> some View {
        section("Which side", hint: "Undo the set to un-mark a side") {
            grid(count: 2, floor: WatchPanel.glyphChip) {
                ForEach([("left", "L"), ("right", "R")], id: \.0) { value, glyph in
                    chip(
                        glyph: glyph,
                        label: value == "left" ? "Left" : "Right",
                        selected: set.side == value,
                        hint: "Marks this set as the \(value) side"
                    ) {
                        model.setSide(value, on: set.id)
                        WKInterfaceDevice.current().play(.click)
                    }
                }
            }
        }
    }

    // MARK: - How it went

    private func qualities(_ set: WorkoutSet) -> some View {
        let chosen = SetTags.parseQuality(set.quality)
        return section("How it went", hint: qualityHint(chosen)) {
            grid(count: SetTags.qualityKeys.count, floor: WatchPanel.wordChip) {
                ForEach(SetTags.qualityKeys, id: \.self) { key in
                    chip(
                        glyph: nil,
                        label: SetTags.quality[key]?.label ?? key,
                        selected: chosen.contains(key),
                        hint: SetTags.quality[key]?.full ?? key
                    ) {
                        model.toggleQuality(key, on: set.id)
                        WKInterfaceDevice.current().play(.click)
                    }
                }
            }
        }
    }

    /// One tag prints its whole sentence; several print their short labels.
    /// The phone's rule, and for the same reason — three sentences under a
    /// grid is a paragraph, and the reserved height would have to hold the
    /// worst case on every set that has none.
    private func qualityHint(_ chosen: [String]) -> String {
        guard !chosen.isEmpty else { return "Clean unless you say otherwise" }
        if chosen.count == 1, let one = SetTags.quality[chosen[0]] { return one.full }
        return chosen.compactMap { SetTags.quality[$0]?.label }.joined(separator: ", ")
    }

    // MARK: - Parts

    @ViewBuilder
    private func section<Content: View>(
        _ title: String, hint: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: OnyxSpace.xs) {
            Text(title)
                .font(WatchType.label)
                .foregroundStyle(WatchInk.secondary)
                .accessibilityAddTraits(.isHeader)
            content()
            // Always there, so choosing a longer hint does not move the chips
            // under the finger that is still on them.
            Text(hint)
                .font(WatchType.label)
                .foregroundStyle(WatchInk.secondary)
                .lineLimit(2)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, minHeight: 18, alignment: .topLeading)
        }
    }

    private func grid<Content: View>(
        count: Int, floor: Double, @ViewBuilder content: () -> Content
    ) -> some View {
        let columns = WatchPanel.columns(forCount: count, minWidth: floor)
        return LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: CGFloat(WatchPanel.gap)),
                count: columns
            ),
            spacing: CGFloat(WatchPanel.gap),
            content: content
        )
    }

    /// One choice.
    ///
    /// ── THE RING IS THE STATE, THE WAY IT IS ON PAGE ONE ────────────────────
    /// The phone tints its four kind chips with four of the design system's
    /// existing hues, and that is right on a phone: four otherwise identical
    /// chips need something to read as a scale before you pick one. Here they
    /// are not identical — each carries its letter — and `WatchInk`'s header
    /// spends three paragraphs on why this device has two inks and no more.
    /// So state is a 2 pt border, which is the same thing focus is on the load
    /// row twenty points up, and the letter does the distinguishing.
    private func chip(
        glyph: String?, label: String, selected: Bool, hint: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                if let glyph {
                    Text(glyph)
                        .font(WatchType.name)
                        .fontWeight(.heavy)
                        .foregroundStyle(selected ? WatchInk.primary : WatchInk.secondary)
                }
                Text(label)
                    .font(WatchType.label)
                    .foregroundStyle(selected ? WatchInk.primary : WatchInk.secondary)
                    // Two lines, so "Form broke" breaks after "Form" rather
                    // than shrinking. `WatchPanel.wordChip` is sized for the
                    // longest WORD for exactly this reason.
                    .lineLimit(2)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
            }
            // 34 and not the 52 the phone's chip uses: this panel is three
            // chip rows deep on a display that shows about 98 pt of it, and
            // every point of chip height is a point of scrolling. 34 still
            // clears a glyph over a word at `caption2`.
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                    .fill(selected ? WatchInk.fillActive : WatchInk.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                    .strokeBorder(selected ? WatchInk.commit : .clear, lineWidth: 2)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isLuminanceReduced)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityLabel(label)
        .accessibilityHint(selected ? "Selected. Tap to remove." : hint)
    }
}
