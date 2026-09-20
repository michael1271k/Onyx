// ── THE SMART STACK'S LIVE CARD (W4) ────────────────────────────────────────
// Unfenced, beside `OnyxAccessory.swift` and for the same reason: it is a
// WidgetKit accessory face and it must be drawable from the app target as well
// as from the extension, because an extension-only view is a view nothing can
// photograph (`WorkoutActivityCard`'s header makes the argument at length —
// that file kept a wrong wordmark through a rename for exactly this reason).
//
// ── AND WHY IT IS NOT `WorkoutWatchCard` ────────────────────────────────────
// It nearly is. `WorkoutWatchCard` already draws a running session on a 40 mm
// Smart Stack card — but it takes an `OnyxWorkoutAttributes.ContentState`,
// which is ActivityKit's, which is iOS-only (`ActivityAttributes` is
// `@available(watchOS, unavailable)`) and arrives from the PHONE. That card is
// the phone-present path, forwarded by `supplementalActivityFamilies([.small])`
// and already shipping.
//
// This is the other half: a session logged on a wrist with the phone in a
// locker, which is the case W3 made real. Its input is `LiveWorkoutSnapshot`,
// written by the watch app into the App Group suite, and the two faces are
// deliberately laid out the same so which one you are looking at is never a
// question you have to ask.

import SwiftUI
import WidgetKit
import OnyxCore

public extension OnyxTile {
    /// The live session's face, at one accessory family. The watch bundle's
    /// one call.
    ///
    /// `nil` is the idle state and draws the empty reading rather than
    /// nothing: a card that renders zero height is a card the system keeps a
    /// slot for and the eye reads as a broken widget, and a blank corner of a
    /// watch face is the same thing smaller.
    @MainActor
    static func liveWorkout(_ snapshot: LiveWorkoutSnapshot?, family: WidgetFamily) -> some View {
        LiveWorkoutFace(snapshot: snapshot, family: family)
    }
}

/// Four facts, in the order the wrist asks them: what am I on, how far in,
/// what is my heart doing, how long until the next one.
///
/// ── TWO FAMILIES, AND THEY ARE TWO DIFFERENT QUESTIONS ──────────────────────
/// `.accessoryRectangular` is the Smart Stack card — the one this widget is
/// FOR, and the one that has room for the movement's name. `.accessoryCircular`
/// is a watch-face corner, where there is room for a glyph and three
/// characters, so it draws the one reading you cannot get any other way: the
/// heart rate. Same snapshot, same process, two amounts of room.
///
/// `family` is a parameter rather than read from the environment for the
/// reason `OnyxTile.accessory` gives: `widgetFamily` is get-only outside
/// WidgetKit, and a face that has to be photographed has to be told what it is.
public struct LiveWorkoutFace: View {

    let snapshot: LiveWorkoutSnapshot?
    var family: WidgetFamily = .accessoryRectangular
    @Environment(\.widgetRenderingMode) private var mode

    public init(snapshot: LiveWorkoutSnapshot?, family: WidgetFamily = .accessoryRectangular) {
        self.snapshot = snapshot
        self.family = family
    }

    /// Colour only where the system lets it mean something — the same rule
    /// every accessory face here follows. The Smart Stack renders full colour
    /// on watchOS 11, but a card is a card and the tinted modes exist.
    private var tint: Color? {
        guard mode == .fullColor else { return nil }
        return WorkoutFaceTint.resolve(muscle: snapshot?.primaryMuscle, dayKey: snapshot?.dayKey)
    }

    public var body: some View {
        Group {
            if family == .accessoryCircular {
                circular
            } else if let s = snapshot {
                live(s)
            } else {
                // Not "no workout" — a card in the stack with nothing running
                // is the ordinary state, and an error-shaped empty is how a
                // widget teaches you to distrust it.
                Label("No session running", systemImage: "dumbbell")
                    .font(AccessoryType.sub)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    /// A watch-face corner: the heart, and the rate under it.
    ///
    /// ── NO GAUGE, BECAUSE THERE IS NO GOAL ──────────────────────────────────
    /// The other circular faces in this app draw a `Gauge` when the reading
    /// has a target and a glyph-and-number when it does not
    /// (`AccessoryFace.circular`). A heart rate has no target: a ring filled
    /// against 200 bpm would be a fraction nobody has ever wanted to read,
    /// and drawing one would be the decoration-claiming-to-be-a-measurement
    /// this file's neighbour refuses by name.
    ///
    /// ── AND A DASH IS THE IDLE STATE, NOT AN EMPTY CORNER ───────────────────
    /// `nil` here is "no session, a sensor that has not settled, or a
    /// reading that has aged past two minutes" — `freshBpm`, which is the
    /// same window the phone's `liveBpm` applies to the same sensor. All
    /// three are absences, all print "—" (`WatchTiles`' rule), and none is
    /// 0 — a zero in this corner is a heart that has stopped.
    ///
    /// The ageing matters most here: a session PAUSED for twenty minutes
    /// republishes on the pause, so without it this corner would draw a
    /// twenty-minute-old rate as a live one.
    @ViewBuilder private var circular: some View {
        VStack(spacing: 1) {
            Image(systemName: "heart.fill")
                .font(.system(.callout, weight: .semibold))
                .foregroundStyle(mode == .fullColor ? Color.onyx.danger : .primary)
            Text(snapshot?.freshBpm().map { "\($0)" } ?? "—")
                .font(AccessoryType.ring)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate")
        .accessibilityValue(snapshot?.freshBpm().map { "\($0) beats per minute" } ?? "No reading")
    }

    private func live(_ s: LiveWorkoutSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            // ── THE MOVEMENT IS THE HEADLINE ────────────────────────────────
            // The same call `WorkoutLockCard` made when it dropped its
            // sparkline: what a glance at a wrist between sets is FOR is the
            // name of the lift in front of you. It shrinks rather than
            // truncating, because the catalogue holds the wide and the close
            // grip as separate movements with separate records and a name
            // that ends at the bracket cannot say which you are on.
            Text(s.exercise)
                .font(AccessoryType.title)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 5) {
                // ── THE COUNTDOWN IS THE HERO WHILE IT RUNS ─────────────────
                // Four peers in a 162 pt slot is what the first draft drew —
                // name, sets, rate and clock, all one size — and during a
                // rest exactly one of them is the number you are acting on.
                // One hero per screen, and on this card the hero MOVES: the
                // clock while resting, the set position the rest of the time.
                //
                // ── THE COUNTDOWN IS THE SYSTEM'S, NOT A TIMELINE'S ─────────
                // `Text(timerInterval:)` is ticked by watchOS from a date
                // range, so a rest that visibly drains costs this extension
                // no reloads at all — and reloads are budgeted on a watch.
                // The alternative was an entry per second, which is how the
                // live card becomes the one widget that stops updating.
                //
                // The range is guarded for the reason `restCountdown` in
                // `WorkoutActivityCard` documents: `Text(timerInterval:)`
                // TRAPS on a range whose end is behind its start, and
                // `restEndsAt` is stale by construction here — this process
                // is woken by the system, not by the clock reaching zero.
                if let ends = s.restEndsAt, ends > Date() {
                    Text(timerInterval: Date()...ends, countsDown: true)
                        .font(AccessoryType.hero)
                        .monospacedDigit()
                        // The MOVEMENT's colour, as the rest clock wears on
                        // every other surface — see `WorkoutRestBand.accent`.
                        .foregroundStyle(tint ?? .primary)
                        // A `.timer` text is as wide as its widest reading,
                        // so it grows a digit at ten minutes and shunts what
                        // is beside it. Reserved.
                        .frame(minWidth: 46, alignment: .leading)
                }
                Text("\(s.setsDone)/\(s.setsPlanned)")
                    .font(AccessoryType.sub)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let bpm = s.freshBpm() {
                    // ── THE RED IS ON THE GLYPH, NOT ON THE NUMBER ──────────
                    // Both were the movement's hue in the first draft, which
                    // put two same-coloured, same-sized numerals 200 pt apart
                    // and left the heart glyph as the only thing telling them
                    // apart — on a family that renders VIBRANT on a real
                    // watch face, where both collapse to one luminance.
                    //
                    // A red numeral beside teal ones also reads as a value in
                    // a bad state. The glyph is what carries "heart" — it is
                    // the strongest convention on the platform and it
                    // survives monochrome, because the meaning is in the
                    // shape. So: red heart, ordinary ink on the reading.
                    HStack(spacing: 2) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(mode == .fullColor ? Color.onyx.danger : .primary)
                        Text("\(bpm)")
                            .monospacedDigit()
                    }
                    .font(AccessoryType.sub)
                }
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live workout")
        .accessibilityValue(Self.spoken(s))
    }

    /// One sentence, because swiping through four fragments to assemble
    /// "Bench Press, set 3 of 5, 142 beats" is worse than being told it —
    /// the same call `WorkoutCurrentSet` makes on the phone.
    static func spoken(_ s: LiveWorkoutSnapshot) -> String {
        var parts = ["\(s.exercise), set \(s.setsDone) of \(s.setsPlanned)"]
        if let bpm = s.freshBpm() { parts.append("\(bpm) beats per minute") }
        if let ends = s.restEndsAt, ends > Date() {
            parts.append("resting for \(Int(ends.timeIntervalSinceNow.rounded())) seconds")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - The hue

/// The movement's muscle, falling back to the split, falling back to Train.
///
/// ── WHY IT IS NOT `WorkoutMuscleTag.tint` ───────────────────────────────────
/// That one lives in `Shared/`, which is compiled into the phone app and the
/// phone's widget extension and neither watch target. This is the same rule
/// stated where the watch can reach it — and it is the same rule: the thing
/// that CHANGES between two rests is which movement you are resting before,
/// and the palette already has a hue per muscle.
enum WorkoutFaceTint {
    static func resolve(muscle: String?, dayKey: String?) -> Color {
        if let muscle, !muscle.isEmpty {
            if let landmark = LandmarkMuscle.from(token: muscle) {
                return Color.onyx.muscle(landmark)
            }
            // The literal a bout carries. A treadmill has no mover to name.
            if muscle == "cardio" { return Color.onyx.cardio }
        }
        guard let dayKey, !dayKey.isEmpty else { return OnyxDomain.train.accent }
        return Color.onyx.day(dayKey)
    }
}
