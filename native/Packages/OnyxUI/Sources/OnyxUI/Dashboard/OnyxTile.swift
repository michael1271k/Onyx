// ── MOSTLY iOS ONLY ─────────────────────────────────────────────────────────
// A Home Screen tile, and `WidgetFamily.systemSmall/Medium/Large` do not
// exist on watchOS. The fence starts BELOW the `WidgetId` extension (W7): the
// title, domain, glyph and `isNative` are strings the watch's complication
// gallery names itself with, and none of them touches a system family.
// Everything from `WidgetSize.family` down is the phone's.

import SwiftUI
import WidgetKit
import OnyxCore

// MARK: - The dashboard's tiles are the widgets
//
// ── ONE DRAWING, TWO HOSTS ───────────────────────────────────────────────────
// The web dashboard had thirteen tile bodies of its own, and the widget
// extension had another set that drew the same numbers differently. Here the
// Today grid is COMPOSED from the widget faces: a `WidgetId` names a family and
// a focus, the slot's size names a `WidgetFamily`, and the face that draws is
// the one the Home Screen already draws. Nothing on the grid is new drawing.
//
// ── THE THREE THAT HAVE NO FACE YET ──────────────────────────────────────────
// `bar`, `micros` and `stack` have no widget face and no snapshot field to draw
// from. They stay in the catalogue — the layout algebra and its vectors are the
// web's — but the phone PROJECTS them out of a slot at draw time
// (`OnyxTile.isNative`) and never offers them in the gallery. The stored layout
// is untouched, so the web keeps them; when a wave gives them a face they
// reappear in whatever slot they always held.
//
// `deficit` and `fatigue` were on that list until W12, which gave them the
// series they were waiting for. They draw now, and a device that has been
// carrying them in a stored layout since Wave 5 gets them back in place.

public extension WidgetId {
    /// What the tile is called in the gallery and on a sheet — `WIDGET_META`.
    var title: String {
        switch self {
        case .recovery: "Recovery"
        case .sleep: "Sleep"
        case .vitals: "Vitals"
        case .fuel: "Fuel"
        case .water: "Water"
        case .micros: "Nutrients"
        case .deficit: "Deficit Ledger"
        case .train: "Workout"
        case .bar: "Bar to Beat"
        case .body: "Body"
        case .trajectory: "Trajectory"
        case .muscle: "Muscle Focus"
        case .volume: "Tonnage"
        case .pr: "Latest PR"
        case .consistency: "Consistency"
        case .steps: "Steps"
        case .cardio: "Cardio"
        case .stack: "Stack"
        case .fatigue: "Fatigue"
        case .weekRings: "Week Rings"
        case .soreness: "Soreness"
        case .stress: "Stress"
        case .bedtime: "Bedtime"
        // Not "Daily": the Home Screen already has a widget kind by that name
        // (`OnyxDaily`, the 2x2 ledger) and two things called Daily on one
        // phone is a gallery you cannot choose from. This one is the whole day
        // as one shape, so it is called what it draws.
        case .daily: "Day Rings"
        }
    }

    /// The accent the tile and its sheet wear — the web's eight hues collapsed
    /// onto the four domains.
    var domain: OnyxDomain {
        switch self {
        // `daily` spans all four domains by construction — that is the point
        // of it — so it takes Recover's, the ground the Today tab already
        // stands on (`TodayTabView.onyxScreen(.recover)`). A tile that belongs
        // to every domain has to wear ONE, and the screen's own is the only
        // one that does not claim a winner.
        case .recovery, .sleep, .vitals, .fatigue, .daily: .recover
        // The three the sprint's W4 added that are recovery readings:
        // `OnyxDomain`'s own list puts sleep, readiness, fatigue AND DOMS on
        // Lunar, and the stress index is built out of the same scalars the
        // battery reads. A bedtime is a sleep surface.
        case .soreness, .stress, .bedtime: .recover
        case .fuel, .water, .micros, .deficit, .stack: .fuel
        // `weekRings` draws three domains at once, like `daily` — and takes
        // Train's rather than the screen's, because it is the door to the
        // WEEK (the sprint's W8) and a week is a block of training with food
        // and sleep underneath it. `daily` takes the screen's ground for the
        // opposite reason: it belongs to today, and today has no winner.
        case .train, .bar, .muscle, .volume, .pr, .consistency, .weekRings: .train
        case .body, .steps, .cardio, .trajectory: .body
        }
    }

    var symbol: String {
        switch self {
        case .recovery: "gauge.with.needle"
        case .sleep: "moon.fill"
        case .vitals: "waveform.path.ecg"
        case .fuel: "flame.fill"
        case .water: "drop.fill"
        case .micros: "sparkles"
        case .deficit: "chart.line.downtrend.xyaxis"
        case .train: "dumbbell.fill"
        case .bar: "target"
        case .body: "scalemass.fill"
        case .trajectory: "chart.line.downtrend.xyaxis"
        case .muscle: "figure.arms.open"
        case .volume: "chart.bar.fill"
        case .pr: "trophy.fill"
        case .consistency: "calendar.badge.checkmark"
        case .steps: "figure.walk"
        case .cardio: "heart.fill"
        case .stack: "pills.fill"
        case .fatigue: "battery.25percent"
        case .weekRings: "circle.grid.3x3"
        case .soreness: "bandage.fill"
        case .stress: "brain.head.profile"
        case .bedtime: "bed.double.fill"
        case .daily: "circle.circle"
        }
    }

    /// Whether the phone has a face for it. See the header.
    var isNative: Bool {
        switch self {
        case .bar, .micros, .stack: false
        default: true
        }
    }
}

#if os(iOS)

public extension WidgetSize {
    /// The WidgetKit family a grid size draws at. The wide sizes are a desktop's
    /// and never reach a phone; they draw at the height tier they stand for.
    var family: WidgetFamily {
        switch Dashboard.heightTier(self) {
        case .s: .systemSmall
        case .m: .systemMedium
        default: .systemLarge
        }
    }
}

// The namespace itself is declared UNFENCED in `Accessory/OnyxAccessory.swift`
// (W7), so the watch can call `OnyxTile.accessory`; everything here is the
// phone's half of it.
public extension OnyxTile {
    /// The catalogue as the phone can draw it, in catalogue order.
    static let native: [WidgetId] = Dashboard.widgetIds.filter(\.isNative)

    /// The face for one widget. The caller sets `onyxTileFamily`.
    ///
    /// `@MainActor` because every arm builds a SwiftUI `View` whose initialiser
    /// is main-actor isolated. Without it the switch warned sixteen times, once
    /// per arm, for a fact that was never in doubt: all three call sites
    /// (`DashboardGrid`, `DomainSheets`, `SmartStackView`) are inside a `body`.
    @MainActor
    @ViewBuilder
    static func face(_ id: WidgetId, entry: OnyxTileEntry) -> some View {
        switch id {
        case .recovery: BodyView(entry: entry, focus: .wellbeing)
        case .sleep: BodyView(entry: entry, focus: .sleep)
        case .vitals: VitalsView(entry: entry, focus: .panel)
        case .fuel: FuelView(entry: entry, focus: .calories)
        case .water: FuelView(entry: entry, focus: .water)
        case .train: TrainingView(entry: entry, focus: .today)
        // ── WHY `body` IS THE COMPOSITION FACE AND NOT THE SCALE ────────
        // The scale weight, its target and its trend are the whole of the
        // Trajectory tile now, and drawing them twice on one grid is two tiles
        // answering one question. What "Body" means once the weight has its own
        // tile is what the kilos are MADE of, which is the Composition focus —
        // the same face the Body family widget offers, so the grid is still
        // composed from widget faces rather than from drawing of its own.
        case .body: BodyView(entry: entry, focus: .composition)
        case .trajectory: TrajectoryView(entry: entry)
        case .muscle: MuscleView(entry: entry)
        case .volume: TrainingView(entry: entry, focus: .volume)
        case .pr: TrainingView(entry: entry, focus: .records)
        case .consistency: ConsistencyView(entry: entry)
        case .steps: StepsView(entry: entry)
        case .cardio: TrainingView(entry: entry, focus: .cardio)
        case .deficit: DeficitLedgerView(entry: entry)
        case .fatigue: FatigueStackView(entry: entry)
        case .weekRings: WeekRingsView(entry: entry)
        case .soreness: SorenessView(entry: entry)
        case .stress: StressView(entry: entry)
        case .bedtime: BedtimeView(entry: entry)
        case .daily: MegaView(entry: entry)
        case .bar, .micros, .stack:
            TileNote(caption: id.title.uppercased(), text: "No face for this one yet.")
        }
    }

    // MARK: The generic kind's family trap (W5)
    //
    // `supportedFamilies` is static per WidgetKit kind, and ONE kind now draws
    // every tile — so a Bedtime placed at Large and a Day Rings placed at Small
    // are both legal placements the catalogue has no body for. The face clamps
    // DOWN: the largest size at or below the host that `Dashboard.widgetSizes`
    // lists, drawn through `onyxTileFamily` exactly as the app's grid asks for
    // a size. Down and never up, because a Small drawn inside a Large is a
    // tile with air around it, and a Large drawn inside a Small is a tile with
    // its bottom two thirds cut off.

    /// The family the tile actually draws at inside `host`, or nil when the
    /// catalogue has nothing at or below it (`daily` at Small).
    static func drawableFamily(_ id: WidgetId, host: WidgetFamily) -> WidgetFamily? {
        let sizes = Dashboard.widgetSizes[id] ?? []
        let cap: Int
        switch OnyxSize(host) {
        case .small: cap = 0
        case .medium: cap = 1
        case .large: cap = 2
        }
        return [WidgetSize.s, .m, .l].prefix(cap + 1).last { sizes.contains($0) }?.family
    }

    /// `face`, clamped to a size the tile has a body for; the note when it has
    /// none. The widget extension's one call for the generic kind.
    @MainActor
    @ViewBuilder
    static func clamped(_ id: WidgetId, host: WidgetFamily, entry: OnyxTileEntry) -> some View {
        if let family = drawableFamily(id, host: host) {
            face(id, entry: entry).environment(\.onyxTileFamily, family)
        } else {
            // Its own container background: the faces set theirs at their
            // root, and a widget body with none is drawn on WidgetKit's
            // default white.
            TileNote(caption: id.title.uppercased(), text: "Needs a larger widget")
                .containerBackground(Color.onyx.base, for: .widget)
        }
    }
}

// MARK: - Steps
//
// The one focus the four families never gave a face of its own: steps is a
// register of the Vitals panel and a quadrant of Daily, both of which draw six
// other things beside it. A tile called "Steps" draws steps.

public struct StepsView: View {
    let entry: OnyxTileEntry
    @Environment(\.widgetFamily) private var hostFamily
    @Environment(\.onyxTileFamily) private var tileFamily
    @Environment(\.widgetRenderingMode) private var mode
    private var size: OnyxSize { OnyxSize(tileFamily ?? hostFamily) }
    private var mono: Bool { mode == .accented }

    public init(entry: OnyxTileEntry) { self.entry = entry }

    public var body: some View {
        face.onyxMarked(monochrome: mono, hidden: entry.isStale)
    }

    @ViewBuilder private var face: some View {
        let s = entry.snapshot
        let spec = FocusSpec.steps(s)
        switch size {
        case .small:
            FocusFace(spec: spec, stale: entry.isStale, age: entry.age, mono: mono)
        case .medium, .large:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Caption(spec.caption, color: mono ? .white : spec.accent)
                    Spacer(minLength: 0)
                    if entry.isStale { StaleTag(age: entry.age) }
                }
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    BigValue(value: spec.hero, size: size == .large ? 44 : 30, color: .white)
                    if let goal = s?.steps.goal {
                        Text("of \(goal)").font(OnyxWidgetType.face(11)).foregroundStyle(Color.onyx.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if let sub = spec.sub {
                        Text(sub).font(OnyxWidgetType.face(11, weight: .semibold)).foregroundStyle(Color.onyx.textSecondary)
                    }
                }
                Rail(progress: spec.progress, color: mono ? .white : spec.accent)
                if let trend = s?.steps.trend, trend.count >= 2 {
                    Sparkline(points: trend.map(\.v), baseline: s?.steps.goal.map(Double.init),
                              color: mono ? .white : spec.accent, zeroBased: true)
                        .frame(maxHeight: .infinity)
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Muscle focus
//
// The week's sets on the body, against what the phase asked for.
//
// ── WHAT W3 CHANGED, AND WHY IT MATTERED ────────────────────────────────────
// The payload used to be per FAMILY, so the figure could only paint every
// muscle of a family at one intensity: an Upper B that hammered the side delts
// and never touched the front lit all three the same. It now carries the
// sixteen landmarks (`OnyxSnapshot.muscleFocus`) and the eight bars are a
// rollup of them, so the head of the delt the week actually trained is the head
// that lights.
//
// The bars also grade against TARGET rather than against the week's busiest
// family. "Legs 34, Back 21, Chest 18" ranked the week but never said whether
// any of it was enough, and the sheet this tile opens has always answered
// exactly that question — two surfaces, one reading, is the whole point of the
// single accumulator.
//
// ── WHY THE FIGURE IS 56 PT AND NOT AS BIG AS IT FITS ───────────────────────
// It was `maxWidth: .infinity`, which on a medium tile is half the width for a
// shape whose whole job is "roughly here". The body is a KEY to the bars beside
// it, not the reading. 56 pt is the smallest figure whose quads are still
// distinguishable from its calves, and the rest of the tile pays for the
// ranking (§W12).

public struct MuscleView: View {
    let entry: OnyxTileEntry
    @Environment(\.widgetFamily) private var hostFamily
    @Environment(\.onyxTileFamily) private var tileFamily
    @Environment(\.widgetRenderingMode) private var mode
    private var size: OnyxSize { OnyxSize(tileFamily ?? hostFamily) }
    private var mono: Bool { mode == .accented }

    public init(entry: OnyxTileEntry) { self.entry = entry }

    /// Ranked by what is LEFT, then by what was done — the sheet's order, so the
    /// tile and the sheet it opens do not disagree about what matters this week.
    private var families: [OnyxSnapshot.FamilyVolume] {
        (entry.snapshot?.volumeByFamily ?? []).enumerated().sorted { a, b in
            let left = (max(0, Double(a.element.target) - a.element.sets),
                        max(0, Double(b.element.target) - b.element.sets))
            if left.0 != left.1 { return left.0 > left.1 }
            if a.element.sets != b.element.sets { return a.element.sets > b.element.sets }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// One family: its name, its progress against the phase's target, the count.
    ///
    /// A family the plan asks nothing of draws no rail at all rather than a full
    /// or empty one — `progress` is nil there, and `Rail` already renders that
    /// as "unknown". Adductors sits at a target of 0 on a cut, and a full rail
    /// beside it would read as an achievement.
    @ViewBuilder private func bar(_ f: OnyxSnapshot.FamilyVolume) -> some View {
        // The tint stays the FAMILY's in every state. Swapping it to `good` on a
        // met target reads as an achievement everywhere except Legs, whose own
        // colour is a green four ΔE from it — and a bar that changes colour for
        // seven families and not the eighth is worse than one that never
        // changes. The filled rail and the "24/32" carry the verdict.
        let tint = mono ? Color.white : Color.onyx.muscleFamily(f.family)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(f.family.rawValue)
                    .font(OnyxWidgetType.face(10, weight: .semibold))
                    .foregroundStyle(Color.onyx.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                // "12/18", or the bare count when the plan asks for nothing —
                // "12/0" reads as a failure and is the opposite of one.
                Text(f.target > 0 ? "\(Int(f.sets.rounded()))/\(f.target)" : "\(Int(f.sets.rounded()))")
                    .font(OnyxWidgetType.figure(10))
                    .foregroundStyle(tint)
            }
            Rail(progress: f.progress, color: tint, height: 3)
        }
    }

    /// Per LANDMARK, graded against that muscle's own target — the same rule the
    /// sheet's figure uses, computed once on the payload.
    private var worked: [String: Double] { entry.snapshot?.muscleWorked ?? [:] }

    public var body: some View {
        face.onyxMarked(monochrome: mono, hidden: entry.isStale)
    }

    @ViewBuilder private var face: some View {
        let accent = mono ? Color.white : OnyxDomain.train.accent
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Caption("MUSCLE FOCUS", color: accent)
                Spacer(minLength: 0)
                if entry.isStale { StaleTag(age: entry.age) }
            }
            // Not `families.isEmpty`: a phase with targets and no sets yet has
            // eight rows and nothing in them, and "Legs 0/32" on a Monday
            // morning is a to-do list, not an empty state.
            if families.allSatisfy({ $0.sets == 0 }) {
                OnyxChartEmpty("No sets logged this week.", compact: true)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    OnyxAtlasFigure(side: .front, worked: worked, color: accent, monochrome: mono)
                        .frame(width: 56)
                        .frame(maxHeight: .infinity)
                    if size != .small {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(families.prefix(size == .large ? 6 : 3)) { f in
                                bar(f)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

/// A face for a widget the phone cannot draw yet — the caption it will wear and
/// one line saying when.
struct TileNote: View {
    let caption: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Caption(caption, color: Color.onyx.textTertiary)
            Text(text).font(OnyxWidgetType.face(11)).foregroundStyle(Color.onyx.textSecondary)
            Spacer(minLength: 0)
        }
    }
}

#endif
