import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

/// Nine themes, each shown as the palette it actually becomes.
///
/// ── WHY THIS IS A SCREEN AND NOT A SECTION ──────────────────────────────────
/// The chips were meant to sit inline on the Settings hub. They cannot. A theme
/// write changes `@AppStorage(OnyxTheme.key)`, `OnyxApp`'s `.id` hangs off that
/// value, and re-identifying the root throws away the entire view tree — the
/// `NavigationStack`'s path and the `TabView`'s selection with it. Inline,
/// tapping a preset would apply the theme AND throw the user out of Settings in
/// the same tap, which reads as a crash rather than as a choice.
///
/// Every tap therefore edits a DRAFT, and the draft is committed once, on the
/// way out — the shape `OnyxNumberField` already uses for a number, and the one
/// moment when throwing the tree away costs nothing, because this screen is
/// being torn down anyway.
///
/// ── WHAT W2 TOOK OFF THIS SCREEN, AND WHY ───────────────────────────────────
/// Two `ColorPicker`s, two mood sliders, a four-capsule preview of the derived
/// ramps and a "Reset to Ion" button. All five were ways of describing a
/// palette; the grid below IS the palette. Each swatch is a live mesh of the
/// four domain accents the theme resolves to, so what used to be a preview
/// under the controls is now the control.
///
/// The pickers went for a second reason: an arbitrary pair of hues is a theme
/// nothing was measured against. The nine in `OnyxTheme.presets` are solved
/// inside the contrast guard and spread ≥ 35° apart on the hue circle; a
/// hand-picked pair is neither, and the hue band the contrast sweep found
/// (114°–160° of primary rotation) was reachable only through a picker. With
/// them gone, the palette is always one of nine known-good ones — and
/// `Color.onyxHex`, `OnyxTheme.picked` and `OnyxTheme.swatch`, which existed
/// only to serve a picker, went with them.
///
/// ── AND WHY IT REFUSES TO WRITE DURING A WORKOUT ────────────────────────────
/// The same rebuild takes `WorkoutTabView`'s live `LoggerModel` with it
/// (`AppEnvironment.isSessionLive`). No set would be lost — they are in the
/// event log the moment they are logged — but the clock, the rest timer and the
/// deck cursor would be, mid-session. The section says so and refuses.
struct AppearanceView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    /// What the grid edits. Seeded from the live theme, never written back to
    /// it until `commit` — see the note above.
    ///
    /// `base` and not `spec`: `current.spec` carries the training block's mood
    /// offset, and seeding from it would light no chip during a cut and then
    /// commit the shifted spec back over the user's pick.
    @State private var draft = OnyxTheme.current.base

    private var locked: Bool { environment.isSessionLive }

    var body: some View {
        Form {
            Section {
                presets
            } header: {
                // Only when it is locked. An "Appearance" header under an
                // "Appearance" title is the same word twice, and at AX5 it was
                // the largest thing on the screen — a heading that repeats the
                // title is not a heading, it is an obstacle to the controls.
                if locked {
                    HStack(spacing: OnyxSpace.xs) {
                        Image(systemName: "lock.fill")
                        Text("Locked while a workout is running")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.onyx.textSecondary)
                }
            } footer: {
                Text(footer)
            }
        }
        .onyxFormBackground()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear(perform: commit)
        // iOS never calls `onDisappear` on a process it jettisons, so a pick
        // made and then backgrounded would be lost without this. `commit` is
        // guarded and idempotent, so the two paths cannot double-write.
        .onChange(of: scenePhase) { _, phase in if phase != .active { commit() } }
    }

    // MARK: - The grid

    /// Three fixed columns, nine themes, three rows.
    ///
    /// FIXED and not `.adaptive`: the grid is a 3 × 3 and reads as one, and an
    /// adaptive minimum would reflow it to 2 × 5 at the first Dynamic Type step
    /// that made a name wide — which turns a square of swatches into a list and
    /// loses the one thing the layout is for. The names are carried by
    /// `minimumScaleFactor` instead: nine names, the longest "Verdigris", and
    /// shrinking one by a third at AX5 is a legible name where truncating it to
    /// "Verdigr…" is a theme picker that has stopped naming its themes.
    ///
    /// Selection is DERIVED — `draft == preset.spec` — so exactly one chip is
    /// lit and there is no tenth "Custom" state to maintain.
    ///
    /// ── LOCKED, THE CHIPS KEEP THEIR INK ────────────────────────────────────
    /// `.disabled` on the section desaturated the swatches, and a grey swatch
    /// is a broken control rather than an unavailable one — it also takes away
    /// the one question a locked Appearance screen can still answer, which is
    /// which theme is on. So the grid stops taking touches and keeps its
    /// colour, and the header above says why.
    private var presets: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: OnyxSpace.s), count: 3),
            spacing: OnyxSpace.m
        ) {
            ForEach(OnyxTheme.presets.indices, id: \.self) { index in
                let preset = OnyxTheme.presets[index]
                Button { draft = preset.spec } label: { chip(preset) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.name)
                    .accessibilityValue(preset.spec.moodWord)
                    .accessibilityAddTraits(draft == preset.spec ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, OnyxSpace.xs)
        .allowsHitTesting(!locked)
        // `allowsHitTesting` stops a finger, not the rotor: without this a
        // locked screen would still let VoiceOver activate a chip and move the
        // selection ring to a theme that is never written — the one thing a
        // locked Appearance screen has to get right.
        .accessibilityRespondsToUserInteraction(!locked)
    }

    /// One preset: its palette, its name, its mood.
    ///
    /// ── THE TWO THINGS A FIXED 3-UP GRID GETS WRONG AT AX5, AND THE FIXES ───
    /// `minimumScaleFactor` is 0.5 and not 0.6, because "Nocturne" at the
    /// largest accessibility size in a 110 pt column needs 0.55 and the first
    /// shot of this screen came out reading "Noctur…".
    ///
    /// And the chip is TOP-aligned in its cell. A `LazyVGrid` row is as tall as
    /// its tallest cell and centres the others in it, so three names that
    /// scaled by three different factors put their three swatches at three
    /// different heights — a grid of squares that photographed as a staircase.
    private func chip(_ preset: (name: String, spec: OnyxThemeSpec)) -> some View {
        let selected = draft == preset.spec
        return VStack(spacing: OnyxSpace.xs) {
            swatch(OnyxTheme(spec: preset.spec), selected: selected)
            Text(preset.name)
                .onyxType(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.onyx.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            // What the chroma/lift column comes to, in one word. The two
            // sliders said the same thing in two numbers nobody could read as
            // a colour; `OnyxThemeSpec.moodWord` derives this from those exact
            // numbers, so the label cannot drift from the mood it names.
            Text(preset.spec.moodWord)
                .onyxType(.micro)
                .foregroundStyle(Color.onyx.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
    }

    /// The palette itself: a 2 × 2 mesh of the four domain accents this theme
    /// resolves to, drawn from `OnyxTheme(spec:)` rather than from `current`.
    ///
    /// ── WHY THE FOUR DOMAINS AND NOT THE TWO CHOSEN HUES ────────────────────
    /// The old chip drew a hard 50/50 split of the primary and the secondary,
    /// which is the two hexes a picker edited — and with the picker gone, those
    /// two are no longer what a theme IS. Train and Fuel are the picks; Body
    /// and Recover are derived and carry the whole of the mood knob, so a
    /// swatch without them shows the half of a theme that never moves. Four
    /// corners, one per `OnyxDomain`, in `allCases` order.
    ///
    /// Each corner is the domain's ACCENT — `ramp(_:).start`, which is what
    /// `OnyxDomain.accent` is — and not a point along the ramp: the two-stop
    /// ramp exists for gradients, and a midpoint of Solar is the muddy salmon
    /// `OnyxDomain.accent` already refuses to draw. The mesh does the blending.
    ///
    /// The tick sits INSIDE the swatch so the grid does not reflow when the
    /// selection moves, and it is `base` — true black — because black on any
    /// colour the contrast guard allows is at least 4.77:1, measured across the
    /// hue circle at both clamp edges.
    private func swatch(_ theme: OnyxTheme, selected: Bool) -> some View {
        let corners = OnyxDomain.allCases.map { theme.ramp($0).start }
        return MeshGradient(
            width: 2,
            height: 2,
            points: [.init(0, 0), .init(1, 0), .init(0, 1), .init(1, 1)],
            colors: corners
        )
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                .strokeBorder(
                    selected ? Color.onyx.textPrimary : Color.onyx.hairline,
                    lineWidth: selected ? 2 : 0.5
                )
        }
        .overlay {
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.onyx.base)
            }
        }
    }

    // MARK: - Copy

    private var footer: String {
        let what = """
            Each swatch is the theme's own four accents — training, nutrition, \
            body and recovery — blended. Picking one moves all twenty-six \
            colours the app draws, including all sixteen muscles. The word \
            under each name is its mood: how saturated and how light the \
            derived colours sit. A cut, a bulk or a deload week then shifts \
            that mood on its own, and shifts back when the block ends; the two \
            accents at the top of each swatch never move. Widgets and the watch \
            follow on their next refresh.
            """
        guard locked else { return what }
        return what + "\n\n" + """
            Locked while a workout is running: a colour change rebuilds every \
            screen, and the live session's clock, rest timer and deck position \
            are held in memory. It unlocks when the workout is finished.
            """
    }

    // MARK: - The one write

    /// Persist the draft, then tell the two processes that do not share this
    /// one's memory.
    ///
    /// `save` normalises, so what lands may not be exactly what was picked —
    /// which is why nothing here reads the draft back afterwards: the view is
    /// already on its way out and the next appearance seeds from `current`.
    private func commit() {
        // `normalised()` on BOTH sides: `current.base` is always normalised, so
        // comparing a raw draft against it says "changed" for any pick the
        // contrast guard moved — and then spends a widget reload and a watch
        // push writing a blob that is byte-identical to the one already there.
        guard !locked, draft.normalised() != OnyxTheme.current.base else { return }
        OnyxTheme.save(draft, to: AppDatabase.appGroupDefaults())
        environment.themeDidChange()
    }
}
