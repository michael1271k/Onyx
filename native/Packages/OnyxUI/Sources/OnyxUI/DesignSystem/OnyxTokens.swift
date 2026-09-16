import SwiftUI
import OnyxCore

/// Onyx — the semantic token layer. Colour and geometry; type lives in
/// `OnyxType.swift`.
///
/// ── WHAT THIS REPLACED ──────────────────────────────────────────────────────
/// `OnyxPalette` was a Tailwind transliteration: forty flat hexes carried over
/// from the web app's `lib/theme/palette.ts` so the web app and the first native screens
/// could be diffed by eye. It did its job and it was not the design. This file
/// is the design — four domain accents, text at three weights, and a short list
/// of fixed semantic hues — and every screen reads it.
///
/// The Live Logger was its last reader and Wave 2.4 re-skinned it, so the file
/// is gone. `OnyxUITests/TokenDisciplineTests.swift` (run by `npm run swift:ui`
/// inside `npm run check`) keeps it gone.
///
/// ── WHAT CHANGED IN TOKENS v2 (Phase 2 §3.2) ────────────────────────────────
/// Every accent came down two steps. The v1 palette was Ion `#7C5CFF` and Tide
/// `#3DFFB0` — full-saturation hues on true black, which is the exact recipe
/// for a screen that reads as a web app in a new font: the accent shouts, the
/// glass under it tints, and every number has to compete with its own label's
/// colour. Desaturating is not a taste change, it is what lets the material
/// carry the hierarchy instead of the hue.
///
/// ── THE RULE THIS FILE MAKES ENFORCEABLE ────────────────────────────────────
/// No raw hex in any view. Hexes live here, views name meanings, and
/// `OnyxUITests/TokenDisciplineTests.swift` fails the build if a `0x` or a
/// `Color(red:` appears under `Features/`. A token you cannot name is a token
/// you have not designed yet.
///
/// Two files may hold a hex: this one (the DEFAULT palette, `defaultDomainHex`
/// and `defaultMuscleHex`) and `OnyxTheme.swift` (the preset table). The
/// domain stops and the sixteen muscles are read through `OnyxTheme.current`,
/// so a theme change reaches every static `Color.onyx.*` call site without an
/// Environment and without a call-site edit.

// MARK: - Domains

/// The four accents. One per domain, and a screen belongs to exactly one.
///
/// ── WHY FOUR AND NOT ONE PER SCREEN ─────────────────────────────────────────
/// The web app grew a colour per concept — ember for calories, emerald for
/// protein, sapphire for carbs, gold for fat, amethyst for a day, garnet for
/// muscle mass — and the result is that colour stopped meaning anything: every
/// screen is a different rainbow, so nothing on any of them stands out. Four
/// accents keyed to DOMAINS means the hue tells you where you are before you
/// read a word, and the one tinted thing on a screen is the one that matters.
public enum OnyxDomain: String, CaseIterable, Sendable {
    /// Ion — logger, PRs, volume, muscle. Indigo → sky.
    case train
    /// Solar — nutrition, levers, water. Honey → coral.
    case fuel
    /// Tide — composition, atlas intensity, cardio. Teal → deep teal.
    case body
    /// Lunar — sleep, readiness, fatigue, DOMS. Lavender → mist.
    case recover

    /// The eight stops as designed — the DEFAULT theme. `OnyxTheme` derives
    /// every other theme from these by hue rotation, so a number here is the
    /// palette's origin, not merely its first value.
    public static let defaultDomainHex: [OnyxDomain: (start: UInt32, end: UInt32)] = [
        .train:   (start: 0x6B78F0, end: 0x4FB6E8),
        .fuel:    (start: 0xE3A650, end: 0xE07A7A),
        .body:    (start: 0x46B39D, end: 0x2E9AA6),
        .recover: (start: 0xA79FD6, end: 0xC9D3EE),
    ]

    /// The mesh's first stop. Also the accent when only one colour will do.
    ///
    /// Read through `OnyxTheme.current`: the dictionaries are total over the
    /// enum, so the `!` is a programming error, never data.
    public var start: Color { OnyxTheme.current.start[self]! }

    /// The mesh's second stop.
    public var end: Color { OnyxTheme.current.end[self]! }

    /// What a `Section` header, a `Gauge` tint or a selected row is coloured.
    ///
    /// The START stop rather than a computed midpoint: a midpoint of Solar
    /// (`#E3A650` → `#E07A7A`) is a muddy salmon that reads as neither warning
    /// nor warmth, and the two-stop ramp exists for gradients, not for solids.
    public var accent: Color { start }

    /// A fixed offset along the mesh, 0 = `start` … 1 = `end`.
    ///
    /// §3.2: split colours, macro rails and set states "derive from the domain
    /// accent's mesh at fixed offsets". This is the one function that derives
    /// them, so a tile never mixes a colour of its own.
    public func at(_ t: Double) -> Color {
        start.mix(with: end, by: min(max(t, 0), 1))
    }

    /// The gradient both the mesh bleed and any tinted fill are built from.
    public var ramp: LinearGradient {
        LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// `OnyxDomain.forMuscle` and `OnyxDomain.forFamily` lived here until W3 and are
// deliberately GONE. They answered "which of the four domain accents owns this
// muscle", which collapsed chest, three delts and three arm muscles onto one
// indigo — so a legend of eight families drew four colours, and "Side delts 0/7"
// looked exactly like "Chest 18/18". A muscle's colour is now the muscle's own
// (`Color.onyx.muscle`), keyed to its family (`Color.onyx.muscleFamily`).
// Nothing reads a domain for a muscle any more; do not re-add the fold.
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - Semantic colours

extension Color {

    /// `Color.onyx.textPrimary`. The only colours a view is allowed to name.
    ///
    /// Lowercase on purpose: it reads as a namespace at the call site, which is
    /// what it is, and `Color.Onyx.textPrimary` would read as a type.
    public enum onyx {

        // ── Ground ───────────────────────────────────────────────────────────

        /// True black. OLED pixels that are off draw no power and have no edge,
        /// which is why every material above them reads as a real layer rather
        /// than a lighter rectangle on a dark grey one.
        public static let base = Color.black

        /// 0.5 pt at 8 % white, and only where content meets chrome. Hierarchy
        /// here is material weight; a border drawn between two things that are
        /// already separated by material is noise.
        public static let hairline = Color.white.opacity(0.08)

        /// Ink at a weight the three text tokens do not name — for a FILL or a
        /// STROKE that is ink rather than type: the body atlas's unworked
        /// silhouette, a baseline tick, a scrim.
        ///
        /// ── WHY A TOKEN WHEN THE ANSWER IS ALWAYS WHITE ────────────────────
        /// It does not rotate with the theme, and it must not: the atlas's
        /// empty body is the ABSENCE of a reading, and a hue there would make
        /// "nothing recorded" look like a value. What the token buys is that
        /// the app has one ink in one file. A widget face that spells
        /// `.white.opacity(0.09)` is indistinguishable, in review, from a face
        /// nobody has themed yet — which is precisely how the tiles came to be
        /// the last un-themed surface in the app (W8).
        ///
        /// Not `textPrimary.opacity(_:)`: that would compound 0.92 into every
        /// caller's number and make 0.08 here mean something different from
        /// 0.08 in `hairline`.
        public static func ink(_ opacity: Double) -> Color { Color.white.opacity(opacity) }

        // ── Text ─────────────────────────────────────────────────────────────

        public static let textPrimary = Color.white.opacity(0.92)
        public static let textSecondary = Color.white.opacity(0.62)
        /// 40 %, and it fails 4.5:1 BY DESIGN — so it is only ever correct for a
        /// label whose absence would cost the reader nothing: a unit suffix, a
        /// row count, a timestamp already spoken by VoiceOver. Never a value,
        /// never a control label, never the only copy of a fact.
        public static let textTertiary = Color.white.opacity(0.40)

        /// A routine day's own stored accent — `routines.accent`, an RGB integer
        /// the user picked when they built the deck.
        ///
        /// ── WHY THIS IS A TOKEN AND NOT A `Color(hex:)` IN THE VIEW ─────────
        /// It reads like a violation of the one native design rule and is not:
        /// nothing is being SPELLED OUT, a stored value is being decoded. But
        /// `TokenDisciplineTests` scans text, not intent, so the call site
        /// was indistinguishable in review from a designer-invented hex — which
        /// is exactly the confusion the rule exists to prevent.
        ///
        /// Decoding it here costs one function and makes the view name a
        /// meaning, which is what the rule actually asks for. Negative or
        /// out-of-range values clamp to the train accent rather than to black,
        /// which would draw an invisible rail.
        public static func routineAccent(_ stored: Int) -> Color {
            guard stored > 0 else { return OnyxDomain.train.accent }
            return Color(hex: UInt32(truncatingIfNeeded: stored))
        }

        /// Destructive actions, validation failures, and the over-budget segment
        /// of a gauge. Never a chart series, never an accent.
        public static let danger = Color(hex: 0xE5484D)

        // ── Accents ──────────────────────────────────────────────────────────

        public static func accent(_ domain: OnyxDomain) -> Color { domain.accent }

        /// Anything that went the right way: a delta in the good direction, a
        /// session logged, a target met. A muted green rather than Tide's teal —
        /// "yes" and "this is the Body tab" are different statements and the v1
        /// palette said them in the same colour.
        public static let good = Color(hex: 0x4CAF87)

        /// A personal record, and nothing else. §3.2 makes gold the ONLY fifth
        /// hue in the system precisely so that seeing it means one thing: the
        /// number under it has never been beaten.
        ///
        /// ── WHY NOT THE PLAN'S #D9B25F ──────────────────────────────────────
        /// That value sat ΔE76 11.0 from `carbs` #E3A650 — and the two meet on
        /// one widget face, where a honey macro bar and a gold record chip read
        /// as the same colour said twice. Records are the loudest thing the app
        /// has to say, so gold moved UP rather than carbs moving down: L* 74.5 →
        /// 86.3, ΔE76 to carbs 20.8, and no token nearer than that.
        public static let record = Color(hex: 0xFFD35C)

        /// The colour of a `DeltaVerdict`.
        ///
        /// ── WHY THE MAPPING LIVES HERE AND NOT IN THE SCREEN THAT NEEDED IT ──
        /// Whether a kilogram gained is good news is a DOMAIN question — it
        /// depends on the phase and on whether the week is a maintenance week —
        /// and `DeltaVerdict` is the one rule that answers it, with a vector.
        /// What a verdict LOOKS like is a token question, and it was living as
        /// a private four-line switch inside `BodyTrendsView.LedgerSection`. The
        /// moment a second surface wanted the same colours (the composition
        /// tooltip, U6) that switch would have been copied, and the copy is how
        /// two screens end up disagreeing about whether the same number is good.
        ///
        /// `neutral` is deliberately `textSecondary` and not a hue: inside a
        /// maintenance band the honest statement is "this did not move", and a
        /// colour would make it a verdict.
        public static func verdict(_ verdict: Verdict) -> Color {
            switch verdict {
            case .good:    good
            case .bad:     danger
            case .neutral: textSecondary
            }
        }

        // ── Macros & water ───────────────────────────────────────────────────
        //
        // Fixed app-wide and never re-mapped per screen: a bar that is coral in
        // Nutrition and teal in a widget is two facts the reader has to hold.
        // Three of the four are domain stops rather than new hues, so the macro
        // rails still read as Solar and Lunar rather than as a fifth palette.
        //
        // Computed, not stored: a Swift static is lazy and would capture the
        // theme at first read, so a `let` here is a macro rail that ignores the
        // theme switch every other token follows.

        /// Coral — Solar's far stop.
        public static var protein: Color { OnyxDomain.fuel.end }
        /// Honey — Solar's near stop.
        public static var carbs: Color { OnyxDomain.fuel.start }
        /// Lavender — Lunar's near stop.
        public static var fat: Color { OnyxDomain.recover.start }
        /// Sapphire. The one macro-adjacent hue that is not on a domain mesh,
        /// because water is not a macro and must not be mistaken for one.
        public static let water = Color(hex: 0x5AA9E6)
        /// Calories are the Atwater SUM of the three macros, so they take the
        /// domain the three sit on rather than a colour of their own. Use
        /// `OnyxDomain.fuel.ramp` where the fill is a gradient.
        public static var calories: Color { OnyxDomain.fuel.accent }

        /// The colour of a ROUTINE DAY — what tints a calendar ring, a session
        /// chip and the This-week panel — keyed onto the domains by what the day
        /// TRAINS, the same way `MuscleFamily.of` keys a muscle.
        ///
        /// §3.2: upper A/B are Ion at 0.35 / 0.65, legs A/B are Tide at the same
        /// two steps, and Delts & Arms takes Ion's end stop. Two steps in from
        /// each end rather than 0 and 1 — a split colour sits next to the domain
        /// accent on the same screen, and a day drawn in the accent itself reads
        /// as "selected" rather than as "leg day". Push/Pull/Legs mirror the rule
        /// so a Onyx week and a PPL week are the same picture.
        ///
        /// A rest day is the ABSENCE of a session and wears no accent at all.
        public static func day(_ dayKey: String?) -> Color {
            switch dayKey {
            // Onyx-5 (active)
            case "cb_a":    return OnyxDomain.train.at(0.35)
            case "cb_b":    return OnyxDomain.train.at(0.65)
            case "arms":    return OnyxDomain.train.end
            case "legs_a":  return OnyxDomain.body.at(0.35)
            case "legs_b":  return OnyxDomain.body.at(0.65)
            // Onyx-4 (drawer) — mirrors its Onyx-5 counterpart
            case "upper_a": return OnyxDomain.train.at(0.35)
            case "upper_b": return OnyxDomain.train.at(0.65)
            case "lower_a": return OnyxDomain.body.at(0.35)
            case "lower_b": return OnyxDomain.body.at(0.65)
            // PPL legacy — the same rule; push and pull are both upper work.
            case "ppl_push_sun", "ppl_push_thu": return OnyxDomain.train.at(0.35)
            case "ppl_pull_mon", "ppl_pull_fri": return OnyxDomain.train.at(0.65)
            case "ppl_legs_tue":                 return OnyxDomain.body.at(0.35)
            default:        return textTertiary
            }
        }

        /// `day()` for a WORD rather than a ring.
        ///
        /// Identical except on a rest day, where `day()` answers `textTertiary`
        /// — a RING colour (§3.2: "Rest = tertiary grey ring"), and 3.7:1 on
        /// black. A ring may sit at 3.7:1; a label naming the day may not, and
        /// `textTertiary`'s own rule says never the only copy of a fact.
        public static func dayLabel(_ dayKey: String?) -> Color {
            let colour = day(dayKey)
            return colour == textTertiary ? textSecondary : colour
        }

        /// Battery banding — the one place a traffic light is the right
        /// metaphor, because the number genuinely is a fuel gauge. Good above
        /// 60, Solar's honey through the middle, danger below 30, and a reading
        /// that does not exist is text-grey rather than any verdict.
        public static func battery(_ pct: Int?) -> Color {
            guard let pct else { return textSecondary }
            // `Battery`'s cuts, never a second pair of literals: the sentence
            // the Mega tile draws under this figure reads the same two numbers
            // (`CoachSentence`), and a green 59 over "Train light today" is the
            // disagreement one shared constant makes impossible.
            return Double(pct) >= Battery.goodPct ? good
                : Double(pct) >= Battery.lowPct ? OnyxDomain.fuel.accent
                : danger
        }

        /// Effort on the CR-10 ladder, in ink.
        ///
        /// NOT gold. `record` means a personal record app-wide, and the old
        /// palette's `amber` sat one hue away from it, which is how an RPE 8
        /// chip and a PR badge came to read as the same announcement. Effort is
        /// a READING, not a verdict, so it stays in secondary ink until the set
        /// is genuinely hard, takes Solar through the working range, and only
        /// turns to danger at 9.5 — at or past failure, which is the one number
        /// on the ladder worth interrupting someone for.
        public static func effort(_ rpe: Double) -> Color {
            switch rpe {
            case ..<8:   textSecondary
            case ..<9.5: OnyxDomain.fuel.accent
            default:     danger
            }
        }

        /// How sore, in ink — §3.2's severity ramp, stored 0…3.
        ///
        /// Gold is the record colour and this is the one other job it is
        /// allowed: pointing at a THRESHOLD. Moderate soreness is the rung at
        /// which the plan is worth a second look, which is the same kind of
        /// statement as "one more session and this load goes up".
        public static func severity(_ level: Int) -> Color {
            switch level {
            case ..<1: textTertiary
            case 1:    good
            case 2:    record
            default:   danger
            }
        }

        /// A stack item's own colour, as a token.
        ///
        /// ── WHY THE STORED STRING CANNOT BE DRAWN ───────────────────────────
        /// `custom_supplements.color` is a CSS colour written by the web —
        /// sometimes a name, sometimes a hex — and it is carried opaquely all
        /// the way through `OnyxCore` for exactly that reason. Rendering it
        /// would put an arbitrary hue on a screen whose palette is a
        /// measurement (see the muscle landmarks), and a `Features/` file that
        /// spelled the hex would fail `TokenDisciplineTests`. So it is
        /// MAPPED, here, where the tokens live.
        ///
        /// Never `record` and never `danger`: gold means a personal record
        /// app-wide and red means destructive, and a multivitamin is neither.
        /// Anything unrecognised — every hex included — falls to the Fuel
        /// accent, which is the screen's own domain and so is an answer rather
        /// than a placeholder.
        public static func supplement(_ raw: String?) -> Color {
            switch (raw ?? "").trimmingCharacters(in: .whitespaces).lowercased() {
            case "amber", "orange", "yellow":    OnyxDomain.fuel.start
            case "red", "coral", "pink":         OnyxDomain.fuel.end
            case "green", "emerald", "lime":     good
            case "blue", "sapphire", "cyan":     water
            case "purple", "violet", "lavender": OnyxDomain.recover.start
            case "teal":                         OnyxDomain.body.accent
            default:                             OnyxDomain.fuel.accent
            }
        }

        /// How tired, in ink — the 1…5 scale `Fatigue.levels` defines.
        ///
        /// Same three-step ramp as `severity`, deliberately: soreness and
        /// fatigue are the two subjective readings on the Pulse screen and a
        /// reader should not have to learn two colour languages to compare
        /// them. An unlogged slot is tertiary, not green — never having said is
        /// not the same as having said "Fresh".
        public static func fatigue(_ level: Int?) -> Color {
            switch level {
            case .some(1), .some(2): good
            case .some(3):           record
            case .some(4), .some(5): danger
            default:                 textTertiary
            }
        }

        /// Cut or bulk, in ink.
        ///
        /// A phase is a NUTRITION direction that the training deck follows, so
        /// it takes Solar (the food domain) for a deficit and the app's `good`
        /// for a surplus — not a hue of its own. There is no maintenance case:
        /// maintenance is a nutrition LEVER pulled on top of whichever direction
        /// the block runs, and `ProgramPhase` has never had a third value.
        public static func phase(_ phase: ProgramPhase) -> Color {
            switch phase {
            case .cut:  OnyxDomain.fuel.accent
            case .bulk: good
            }
        }

        // ── THE MUSCLE PALETTE ───────────────────────────────────────────────
        //
        // Eight family hues, sixteen landmark shades (founder decision 4). This
        // is the only categorical palette in ONYX, and it is deliberately a
        // LOUDER register than the four domain accents above.
        //
        // ── WHY IT IS ALLOWED TO BE LOUDER THAN THE CHROME ───────────────────
        // The four accents are desaturated because they are chrome: they say
        // which screen you are on, and a screen where the furniture shouts has
        // nothing left to point with. These sixteen are DATA. Their whole job is
        // to be told apart from one another at 8 pt in a legend and at 56 pt on
        // a widget figure, and a category palette that cannot be told apart is
        // not quiet, it is broken — which is what the four-accent collapse made
        // it: chest, three delts and three arm muscles all drew `#6B78F0`.
        //
        // ── HOW THESE SIXTEEN WERE CHOSEN ────────────────────────────────────
        // Generated in OKLCH at a fixed L 0.70 / C 0.17, with the eight family
        // hues solved by coordinate ascent to MAXIMISE the smallest CIEDE2000
        // distance between any two landmarks of different families — scored on
        // the sixteen and not the eight, because a family's darkest step can
        // collide with a neighbour's darkest step while the two anchors sit
        // comfortably apart. The result, measured:
        //
        //   · closest cross-family pair   ΔE 22.8  (Side delts / Forearms)
        //   · closest of the W3 gate four ΔE 22.9  (Biceps / Triceps)
        //   · lowest contrast on black     4.99:1  (Calves)
        //
        // Inside a family the hue is FIXED and only lightness steps, light →
        // dark in `LandmarkMuscle` declaration order, so three teals read as
        // three back muscles rather than as three unrelated colours. Adjacent
        // steps sit at ΔE 5–9: a visible step, and no more, on purpose.
        //
        // A number here is a measurement, not a taste. Re-run
        // `scratchpad/palette.py` before changing one.

        /// A cardio bout's colour — the one movement class the sixteen muscle
        /// hues cannot answer for.
        ///
        /// ── WHY IT IS TIDE AND NOT A SEVENTEENTH HEX ────────────────────────
        /// `MuscleMap` holds no cardio entry, by design: a treadmill has no
        /// primary mover to name. So every surface that colours a movement by
        /// its muscle fell through — the live deck to the DAY's accent (a
        /// treadmill that changed colour depending on which split it opened)
        /// and the session ledger to `.recover` lavender, which is the colour
        /// Core already wears. Neither is an answer; both are a default.
        ///
        /// `OnyxDomain.body` already declares itself the domain of "composition,
        /// atlas intensity, CARDIO", and the cardio sheet has been drawing its
        /// own chrome in that accent since it was written. This is that answer,
        /// said once, so the deck, the ledger and the sheet agree — and it
        /// spends no new colour, which §3.2 has none to spend.
        public static var cardio: Color { OnyxDomain.body.accent }

        /// A muscle FAMILY's colour — what a chart grouping by the eight draws.
        ///
        /// Its MIDDLE landmark's, not a ninth through sixteenth hex of its own.
        /// The ramp is centred on the family's hue, so the middle step already
        /// is the family: Back reads as Upper back's teal, Shoulders as Side
        /// delts' amber, Legs as Glutes' green. Spelling the eight out again
        /// would be eight more numbers that have to be kept equal to eight of
        /// the sixteen by hand — which is the same bookkeeping the single
        /// accumulator exists to abolish, in a palette instead of a count.
        public static func muscleFamily(_ family: MuscleFamily) -> Color {
            // `first` and not `members[count / 2]`: the invariant that every
            // family owns a landmark lives in a `switch` in another module, and
            // a ninth family added without one would trap at draw time in four
            // places rather than fail where the mistake was made.
            let members = family.members
            guard !members.isEmpty else { return textTertiary }
            return muscle(members[members.count / 2])
        }

        /// A LANDMARK's colour: its family's hue, at its own step of the ramp.
        ///
        /// ── WHERE `step:` AND `of:` WENT ─────────────────────────────────────
        /// This used to take "where the muscle sits in the list you happen to be
        /// drawing" and ramp from it, which made Lats one teal in a session that
        /// trained three back muscles and a different teal in a session that
        /// trained one — the same muscle in two colours on two screens of one
        /// app. The step is intrinsic now (`MuscleFamily.step(of:)`), which is
        /// what makes a legend dot and a body region the same colour, so the two
        /// parameters were not merely unused: keeping them would have left the
        /// call site claiming a ramp the function no longer performs.
        public static func muscle(_ muscle: LandmarkMuscle) -> Color {
            OnyxTheme.current.muscle[muscle]!
        }

        /// The sixteen as measured — the DEFAULT theme's muscle palette, in
        /// `LandmarkMuscle` declaration order. `OnyxTheme` rotates all sixteen
        /// by the train accent's hue offset, so the family ramps hold.
        public static let defaultMuscleHex: [LandmarkMuscle: UInt32] = [
            .chest:      0xF66D64,
            .lats:       0x00D4CE,
            .upperBack:  0x00B6B0,
            .lowerBack:  0x009894,
            .frontDelts: 0xFF9F46,
            .sideDelts:  0xE68100,
            .rearDelts:  0xC26C00,
            .biceps:     0x998BFF,
            .triceps:    0x0EA6FF,
            .forearms:   0xB49F00,
            .quads:      0x8AE171,
            .hamstrings: 0x76CC5C,
            .glutes:     0x61B647,
            .adductors:  0x4DA230,
            .calves:     0x388D15,
            .absCore:    0xE66DB6,
        ]
    }
}

// MARK: - Geometry

/// The spacing scale. Five steps, and `Features/` may not spell a number.
///
/// ── WHY A SCALE AT ALL WHEN EVERY VALUE IS ALREADY A NUMBER ─────────────────
/// The screens this replaces used 14 and 16 and 18 interchangeably — not as
/// decisions but as whatever the file next door happened to say. Three values
/// that differ by 2 pt do not read as three levels of relationship; they read as
/// a grid that is slightly off, which is the single loudest "this was not made
/// by a designer" signal an iOS screen can send. Five steps that are visibly
/// different is a hierarchy. Fifteen that are not is noise.
public enum OnyxSpace {
    /// 4 — inside a chip, between a glyph and its label.
    public static let xs: CGFloat = 4
    /// 8 — between the lines of one thought.
    public static let s: CGFloat = 8
    /// 12 — a tile's own padding, and the gap between rows inside it.
    public static let m: CGFloat = 12
    /// 16 — the gap between sections, and the screen's side gutter.
    public static let l: CGFloat = 16
    /// 24 — the gap above a footer CTA, and a sheet's top inset.
    public static let xl: CGFloat = 24

    /// The dashboard grid's gap: `s + 2`.
    ///
    /// The one value that is not a step of the scale, and it is deliberate. The
    /// grid's cells already carry `m` of padding inside their own edge, so a
    /// full `m` between them reads as a 24 pt trench; `s` alone lets two tiles
    /// touch. 10 is the value where a 2-up grid reads as a grid.
    public static let grid: CGFloat = 10
}

/// Concentric squircles: an inner radius is its outer radius minus the padding
/// between them. Corners that are merely "all rounded" read as stickers.
///
/// v2 brought all three down (12/20/32 → 10/16/28). A 20 pt corner on a 160 pt
/// tile is a lozenge; iOS's own widgets, cards and grouped rows sit near 16, and
/// the tiles were reading as web cards partly because of it.
public enum OnyxCorner {
    /// A row inside a tile.
    public static let row: CGFloat = 10
    /// A tile on a screen.
    public static let tile: CGFloat = 16
    /// A presented sheet.
    public static let sheet: CGFloat = 28

    /// The inner radius for content inset by `padding` inside `outer`.
    public static func inner(_ outer: CGFloat, padding: CGFloat) -> CGFloat {
        max(0, outer - padding)
    }
}

// MARK: - Sleep

/// The four sleep stages, each its own token.
///
/// ── WHY NOT FOUR ALPHAS OF ONE HUE ──────────────────────────────────────────
/// v1 derived all four from Lunar at fixed offsets, and the Sleep sheet came out
/// as four lavender bars a reader had to decode from a legend. The stages are
/// not a ramp of one quantity — deep and REM are different KINDS of sleep, and
/// awake is not sleep at all — so they get four hues that stay distinct at a
/// widget's 9 pt legend and in the stacked arc. Deep is the indigo end of night,
/// core keeps Lunar, REM is warm because it is the active stage, and awake is
/// the neutral gap in the night.
public enum OnyxSleepStage: CaseIterable, Sendable {
    case deep, core, rem, awake

    public var color: Color {
        switch self {
        case .deep:  Color(hex: 0x5B62C9)
        case .core:  OnyxDomain.recover.start
        case .rem:   Color(hex: 0xE07A9A)
        case .awake: Color(hex: 0x6E6E78)
        }
    }

    /// The widget label: upper-case, 8 pt, no room for anything longer.
    public var label: String {
        switch self {
        case .deep:  "DEEP"
        case .core:  "CORE"
        case .rem:   "REM"
        case .awake: "AWAKE"
        }
    }

    /// The same stage in a sentence, for the app's rows. `label.capitalized`
    /// would turn REM — an acronym — into "Rem".
    public var title: String {
        switch self {
        case .deep:  "Deep"
        case .core:  "Core"
        case .rem:   "REM"
        case .awake: "Awake"
        }
    }
}


// MARK: - Hex

public extension Color {
    /// `Color(hex: 0xRRGGBB)` — how every token above is spelled.
    ///
    /// Takes an integer rather than a string on purpose: a string initialiser
    /// has to decide what to do with a typo at runtime, and every such API in
    /// the wild answers "silently return black". An `Int` literal that is not a
    /// colour does not compile.
    ///
    /// It is `public` because the widget extension resolves a day's colour the
    /// same way the app does; it is not an invitation to spell a colour in a
    /// view, which the token-discipline test forbids outright.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: opacity
        )
    }
}
