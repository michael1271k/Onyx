import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

/// Eight Stone themes in a fixed 2 × 4, with a live preview of the draft above
/// them (overhaul B3, decision Q17).
///
/// ── WHY THIS IS A SCREEN AND NOT A SECTION ──────────────────────────────────
/// A theme write changes `@AppStorage(OnyxTheme.key)`, `OnyxApp`'s `.id` hangs
/// off that value, and re-identifying the root throws away the entire view
/// tree — the `NavigationStack`'s path and the `TabView`'s selection with it.
/// Every tap therefore edits a DRAFT, and the draft is committed once, on the
/// way out: the one moment throwing the tree away costs nothing, because this
/// screen is being torn down anyway. The preview strip is how the draft is
/// SEEN before that moment — it draws `OnyxTheme(spec: draft)` directly, not
/// `OnyxTheme.current`.
///
/// ── AND WHY IT REFUSES TO WRITE DURING A WORKOUT ────────────────────────────
/// The same rebuild takes `WorkoutTabView`'s live `LoggerModel` with it
/// (`AppEnvironment.isSessionLive`): the clock, the rest timer and the deck
/// cursor would go mid-session. The section says so and refuses.
struct AppearanceView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    /// What the grid edits. Seeded from the live theme's PICK (`base`, not
    /// `spec`, which carries the training block's mood offset), never written
    /// back to it until `commit`.
    @State private var draft = OnyxTheme.current.base

    private var locked: Bool { environment.isSessionLive }

    var body: some View {
        Form {
            Section {
                AppearancePreview(theme: OnyxTheme(spec: draft))
                    // The preview IS a slab; the Form row must not draw a
                    // second card around it (B3 shot).
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                presets
            } header: {
                // Only when it is locked — an "Appearance" header under an
                // "Appearance" title is the same word twice.
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
        // iOS never calls `onDisappear` on a process it jettisons; `commit` is
        // guarded and idempotent, so the two paths cannot double-write.
        .onChange(of: scenePhase) { _, phase in if phase != .active { commit() } }
    }

    // MARK: - The grid

    /// Two fixed rows of four, in `OnyxTheme.presets` order: Slate · Lagoon ·
    /// Sage · Iris, then Clay · Ochre · Moss · Rosewood.
    ///
    /// FIXED and not `.adaptive`: an adaptive minimum reflows the grid to a
    /// list at the first Dynamic Type step that makes a name wide. Names carry
    /// `minimumScaleFactor(0.5)` instead ("Rosewood" in a ~76 pt column at AX5),
    /// and every chip is TOP-aligned so names scaled by different factors do
    /// not put their swatches at different heights (a W2 AX5 trap).
    ///
    /// Selection is DERIVED — `draft == preset.spec` — so exactly one chip is
    /// lit. Locked, the grid stops taking touches but keeps its colour: a grey
    /// swatch reads as broken, and a locked screen still answers "which theme".
    private var presets: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: OnyxSpace.s), count: 4),
            spacing: OnyxSpace.m
        ) {
            ForEach(OnyxTheme.presets.indices, id: \.self) { index in
                let preset = OnyxTheme.presets[index]
                Button { draft = preset.spec } label: { chip(preset) }
                    .buttonStyle(OnyxPressStyle(scale: 0.95))
                    .accessibilityLabel(preset.name)
                    .accessibilityAddTraits(draft == preset.spec ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, OnyxSpace.xs)
        .allowsHitTesting(!locked)
        // `allowsHitTesting` stops a finger, not the rotor.
        .accessibilityRespondsToUserInteraction(!locked)
    }

    private func chip(_ preset: (name: String, spec: OnyxThemeSpec)) -> some View {
        let selected = draft == preset.spec
        return VStack(spacing: OnyxSpace.xs) {
            StoneSwatch(accent: OnyxTheme(spec: preset.spec).ramp(.train).start, selected: selected)
            Text(preset.name)
                .onyxType(.caption)
                .fontWeight(selected ? .bold : .semibold)
                .foregroundStyle(selected ? Color.onyx.textPrimary : Color.onyx.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // Capped: eight names in ~76 pt columns scaled by eight
                // different factors at AX5 sat on eight baselines and
                // truncated "Rose…" (B3 shot). The swatch carries the choice;
                // VoiceOver reads the full name.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
    }

    // MARK: - Copy

    private var footer: String {
        let what = """
            The swatch is the theme's accent, drawn as the seam of light in \
            the stone. It moves the app's accents and, a little, its nutrition \
            colours; water, heart rate, sleep and the sixteen muscles keep \
            their own colours in every theme. A cut, a bulk or a deload week \
            shifts the mood on its own and shifts back when the block ends. \
            Widgets and the watch follow on their next refresh.
            """
        guard locked else { return what }
        return what + "\n\n" + """
            Locked while a workout is running: a colour change rebuilds every \
            screen, and the live session's clock, rest timer and deck position \
            are held in memory. It unlocks when the workout is finished.
            """
    }

    // MARK: - The one write

    /// Persist the draft, then tell the widget and watch processes.
    private func commit() {
        // `normalised()` on BOTH sides: `current.base` is always normalised, so
        // a raw draft would read as "changed" for any pick the guard moved.
        guard !locked, draft.normalised() != OnyxTheme.current.base else { return }
        OnyxTheme.save(draft, to: AppDatabase.appGroupDefaults())
        environment.themeDidChange()
    }
}

/// One theme as a slab of stone with its accent as a diagonal seam of light —
/// the app icon's own image, not a four-colour mesh (B3). The selected slab
/// wears a ring in the accent and a check in text ink.
private struct StoneSwatch: View {
    let accent: Color
    let selected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
        ZStack {
            shape.fill(Color.onyx.slab)
            // The seam: a thin diagonal band, lower-left to upper-right, lit
            // at its core and fading at both edges.
            GeometryReader { geo in
                let w = geo.size.width
                Rectangle()
                    .fill(LinearGradient(
                        colors: [accent.opacity(0), accent, Color.white.opacity(0.85), accent, accent.opacity(0)],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: w * 0.14, height: w * 1.6)
                    .rotationEffect(.degrees(45))
                    .position(x: w / 2, y: geo.size.height / 2)
                    .blur(radius: 0.6)
            }
            .clipShape(shape)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.onyx.textPrimary)
                    .padding(4)
                    .background(Circle().fill(Color.onyx.slab))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(4)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            shape.strokeBorder(selected ? accent : Color.white.opacity(0.10), lineWidth: selected ? 2 : 1)
        }
        .accessibilityHidden(true)
    }
}

/// The draft, drawn: a tile, a chip, a macro rail and the water pitcher —
/// three themed inks and one fixed, so the choice is seen against the colour
/// that does not move.
private struct AppearancePreview: View {
    let theme: OnyxTheme

    private var accent: Color { theme.ramp(.train).start }

    var body: some View {
        HStack(alignment: .center, spacing: OnyxSpace.m) {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                HStack(spacing: OnyxSpace.xs) {
                    Circle().fill(accent).frame(width: 6, height: 6)
                    Text("TRAINING").onyxType(.micro, tracking: 0.12).foregroundStyle(accent)
                }
                Text("12.4 t")
                    .onyxType(.display).onyxNumeral()
                    .foregroundStyle(Color.onyx.textPrimary)
                Text("Delts & Arms")
                    .onyxType(.caption).fontWeight(.semibold)
                    .foregroundStyle(accent)
                    .padding(.horizontal, OnyxSpace.s).padding(.vertical, 3)
                    .background(Capsule().fill(accent.opacity(0.16)))
                HStack(spacing: OnyxSpace.xs) {
                    Text("P").onyxType(.micro).fontWeight(.bold).foregroundStyle(theme.proteinInk)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.onyx.hairline)
                            Capsule().fill(theme.proteinInk).frame(width: geo.size.width * 0.72)
                        }
                    }
                    .frame(height: 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PitcherFigure(ml: 1900, goalMl: 3000)
                .frame(width: 56, height: 70)
        }
        .padding(OnyxSpace.m)
        .onyxGlass(.tile)
        // A picture of a tile: tiles cap their type, so the picture does too.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the selected theme")
    }
}
