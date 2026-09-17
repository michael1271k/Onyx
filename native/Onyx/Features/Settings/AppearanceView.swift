import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

/// Two hues, a mood, and the twenty-six colours the app derives from them.
///
/// ── WHY THIS IS A SCREEN AND NOT A SECTION ──────────────────────────────────
/// The chips and the pickers were meant to sit inline on the Settings hub. They
/// cannot. A theme write changes `@AppStorage(OnyxTheme.key)`, `OnyxApp`'s
/// `.id(themeJSON)` hangs off that value, and re-identifying the root throws
/// away the entire view tree — the `NavigationStack`'s path and the `TabView`'s
/// selection with it. So, inline:
///
///   · tapping a preset would apply the theme AND throw the user out of
///     Settings in the same tap, which reads as a crash rather than a choice;
///   · a `ColorPicker` bound to the store would tear down the UIKit sheet
///     presenting it on the first frame of a drag. It writes its binding
///     continuously (`didSelect:continuously:`) and SwiftUI surfaces no
///     end-of-edit signal, so there is no frame at which writing is safe.
///
/// Every control here therefore edits a DRAFT, and the draft is committed once,
/// on the way out — the shape `OnyxNumberField` already uses for a number, and
/// the one moment when throwing the tree away costs nothing, because this
/// screen is being torn down anyway.
///
/// ── AND WHY IT REFUSES TO WRITE DURING A WORKOUT ────────────────────────────
/// The same rebuild takes `WorkoutTabView`'s live `LoggerModel` with it
/// (`AppEnvironment.isSessionLive`). No set would be lost — they are in the
/// event log the moment they are logged — but the clock, the rest timer and the
/// deck cursor would be, mid-session. The section says so and refuses.
struct AppearanceView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    /// What the controls edit. Seeded from the live theme, never written back
    /// to it until `commit` — see the note above.
    @State private var draft = OnyxTheme.current.spec

    /// The swatch grows with the type and then stops: at AX5 an unclamped
    /// `@ScaledMetric` is a 68 pt disc that pushes the name out of its own chip.
    @ScaledMetric(relativeTo: .body) private var swatchSize: CGFloat = 22
    /// The grid's own adaptive minimum grows with the type, so two columns
    /// become one — the escape `OnyxFieldCell` documents, and the reason there
    /// is no horizontal scroll view here. A row of chips that ran off the right
    /// edge would be unreachable to VoiceOver and invisible in a screenshot.
    ///
    /// ── WHY 126 AND NOT 100 (W3) ────────────────────────────────────────────
    /// 100 fitted three columns and the old table's longest name was five
    /// characters. "Terracotta" is ten: at `.caption` semibold that is ~67 pt of
    /// text, and with the 22 pt swatch, its 8 pt gap and 12 pt of padding each
    /// side the chip needs ~121. Three columns cannot be made to hold that on a
    /// 393 pt phone, so the grid is TWO columns and five rows. The alternative
    /// was `.lineLimit(1)` doing its job — truncating the name — and a theme
    /// picker whose chips read "Terracot…" is a picker that has stopped naming
    /// its themes.
    @ScaledMetric(relativeTo: .body) private var chipWidth: CGFloat = 126

    private var locked: Bool { environment.isSessionLive }
    private var swatch: CGFloat { min(max(swatchSize, 22), 34) }

    var body: some View {
        Form {
            Section {
                presets
                ColorPicker("Primary", selection: OnyxTheme.picked($draft.primary), supportsOpacity: false)
                    .disabled(locked)
                ColorPicker("Secondary", selection: OnyxTheme.picked($draft.secondary), supportsOpacity: false)
                    .disabled(locked)
                mood
                derived
                // Enabled even on Ion: `OnyxTheme.set` returns early on a spec
                // that has not moved, so the write is idempotent and a second
                // disabled state is a second thing the footer has to explain.
                Button("Reset to Ion") { draft = .default }
                    .disabled(locked)
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

    // MARK: - The presets

    /// Nine pairs, wrapped rather than scrolled.
    ///
    /// Selection is DERIVED — `draft == preset.spec` — so the moment either
    /// picker moves — or either mood slider — no chip is lit and the row has
    /// told the truth without a tenth "Custom" chip to maintain.
    ///
    /// ── LOCKED, THE CHIPS KEEP THEIR INK ────────────────────────────────────
    /// `.disabled` on the section desaturated the swatches, and a grey swatch
    /// is a broken control rather than an unavailable one — it also takes away
    /// the one question a locked Appearance screen can still answer, which is
    /// which theme is on. So the grid stops taking touches and keeps its
    /// colour; the header above says why, and the two system pickers and the
    /// reset take the stock `.disabled` dimming, because hand-rolling a
    /// disabled look for a system control is how a screen stops looking like
    /// the platform.
    private var presets: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: chipWidth), spacing: OnyxSpace.s)],
            alignment: .leading,
            spacing: OnyxSpace.s
        ) {
            ForEach(OnyxTheme.presets.indices, id: \.self) { index in
                let preset = OnyxTheme.presets[index]
                Button { draft = preset.spec } label: { chip(preset) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.name)
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

    /// One preset.
    ///
    /// The swatch is a HARD 50/50 split on the ramp's own diagonal, not a
    /// blend: the two hues sit about 120° apart and their midpoint is a colour
    /// the app never draws (`OnyxDomain.accent` says as much about Solar). The
    /// name is `textPrimary` and never the theme colour — an accent at the
    /// contrast floor is 4.8:1 on black but only ~4.1:1 on this row's material,
    /// which is under AA for the one piece of text a chip has.
    private func chip(_ preset: (name: String, spec: OnyxThemeSpec)) -> some View {
        let selected = draft == preset.spec
        let colours = OnyxTheme.swatch(preset.spec)
        return HStack(spacing: OnyxSpace.s) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        stops: [
                            .init(color: colours.primary, location: 0.5),
                            .init(color: colours.secondary, location: 0.5),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .overlay(Circle().strokeBorder(Color.onyx.hairline, lineWidth: 0.5))
                // Inside the swatch, so the grid does not reflow when the
                // selection moves. Black on any colour the guard allows is at
                // least 4.77:1 — measured across the hue circle at both clamp
                // edges — which is why the tick is `base` and not white.
                if selected {
                    Image(systemName: "checkmark")
                        // Sized from the SWATCH, not from the text style: a
                        // `.caption2` tick scales with Dynamic Type and at AX5
                        // was drawn bigger than the circle holding it, spilling
                        // across the name. The swatch has its own clamp, so
                        // tying the glyph to it is what keeps them together.
                        .font(.system(size: swatch * 0.52, weight: .bold))
                        .foregroundStyle(Color.onyx.base)
                }
            }
            .frame(width: swatch, height: swatch)
            Text(preset.name)
                .onyxType(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.onyx.textPrimary)
                // A tripwire, not a fix: every preset name is three to five
                // characters and fits at AX5. A seventh with a long one should
                // show up as a visible truncation in a shot, not as a row that
                // silently got wider than the phone.
                .lineLimit(1)
        }
        .padding(.horizontal, OnyxSpace.m)
        .padding(.vertical, OnyxSpace.s)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Capsule().strokeBorder(
                selected ? Color.onyx.textPrimary : Color.onyx.hairline,
                lineWidth: selected ? 1.5 : 0.5
            )
        )
        .contentShape(Capsule())
    }

    // MARK: - The mood

    /// The second axis. Two hues say WHICH colours; these two say how deep and
    /// how loud the twenty-four derived ones are.
    ///
    /// They edit the DRAFT like everything else here — `commit()` is still the
    /// one writer — and the `derived` preview below renders from that same
    /// uncommitted draft, so moving either slider shows its effect on all four
    /// ramps for free.
    ///
    /// ── WHY THE TWO SWATCHES ABOVE DO NOT MOVE ──────────────────────────────
    /// Neither knob touches the two chosen accents, and that is not an
    /// oversight: `OnyxTheme` holds them at exactly the hexes the pickers show,
    /// because a picker whose swatch disagreed with the screen would be a
    /// broken control. What moves is everything the app DERIVES — see the
    /// derivation note on `OnyxTheme`.
    @ViewBuilder
    private var mood: some View {
        knob(
            "Saturation",
            value: $draft.chroma,
            range: OnyxThemeSpec.chromaScale,
            step: 0.02,
            reading: "\(Int((draft.chroma * 100).rounded())) %"
        )
        knob(
            "Lift",
            value: $draft.lift,
            range: OnyxThemeSpec.liftOffset,
            step: 0.01,
            // The stored value is an OKLCH lightness offset — 0.03 means
            // nothing to anyone. Shown ×100 and signed, it reads as the small
            // dial it is.
            reading: draft.lift == 0 ? "0" : String(format: "%+d", Int((draft.lift * 100).rounded()))
        )
    }

    private func knob(
        _ label: String, value: Binding<Double>,
        range: ClosedRange<Double>, step: Double, reading: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: OnyxSpace.s) {
                Text(label)
                Spacer(minLength: OnyxSpace.s)
                Text(reading)
                    .onyxType(.caption).onyxNumeral()
                    .foregroundStyle(Color.onyx.textSecondary)
            }
            Slider(value: value, in: range, step: step)
                // The label above is the accessible one; without this the
                // slider announces itself a second time with no name.
                .labelsHidden()
        }
        .disabled(locked)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(reading)
    }

    // MARK: - What the two hues become

    /// The four ramps, resolved from the DRAFT rather than from `current`.
    ///
    /// Without this the screen shows the two colours the user picked and hides
    /// the twenty-four it just changed — and since nothing repaints until the
    /// draft is committed, there would be no way to see what Body, Recover or
    /// the muscle palette had become before leaving. `OnyxTheme(spec:)` resolves
    /// the whole palette in one pass, so this costs one build per edit.
    private var derived: some View {
        let theme = OnyxTheme(spec: draft.normalised())
        return VStack(alignment: .leading, spacing: OnyxSpace.xs) {
            ForEach(OnyxDomain.allCases, id: \.self) { domain in
                let ramp = theme.ramp(domain)
                HStack(spacing: OnyxSpace.s) {
                    Capsule()
                        .fill(LinearGradient(
                            colors: [ramp.start, ramp.end],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: 44, height: 10)
                    Text(domain.rawValue.capitalized)
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textSecondary)
                }
            }
        }
        .padding(.vertical, OnyxSpace.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview")
        .accessibilityValue("Train, fuel, body and recovery ramps for the colours above")
    }

    // MARK: - Copy

    private var footer: String {
        let what = """
            Primary is the training accent; secondary is the nutrition one. \
            Body, recovery and all sixteen muscle colours are rotated from the \
            primary, so moving it moves most of the app. Saturation and lift \
            then set the mood of those derived colours — the two you picked \
            above stay exactly as you picked them. A colour too dark to read on \
            black, or louder than the muscle palette, is pulled back to the \
            nearest one that is not. Widgets and the watch follow on their next \
            refresh.
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
        // `normalised()` on BOTH sides: `current.spec` is always normalised, so
        // comparing a raw draft against it says "changed" for any pick the
        // contrast guard moved — and then spends a widget reload and a watch
        // push writing a blob that is byte-identical to the one already there.
        guard !locked, draft.normalised() != OnyxTheme.current.spec else { return }
        OnyxTheme.save(draft, to: AppDatabase.appGroupDefaults())
        environment.themeDidChange()
    }
}
