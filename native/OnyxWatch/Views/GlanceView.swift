import OnyxCore
import OnyxData
import OnyxUI
import SwiftUI
import WatchKit

/// Page one of the dashboard: readiness as a ring, SIX petals around it —
/// sleep, water, food above; heart, steps, stress below (Precision D1,
/// decision Q22; it was four in the square's corners).
///
/// ── THE BODY TAB'S INSTRUMENT, ON A WRIST ───────────────────────────────────
/// The same six in the same places as the phone's Body ring (`BodyRing`,
/// seam 5): each petal a disc in its FIXED ink with its own progress arc,
/// hollow when there is no reading, filled without an arc when there is a
/// reading and no goal. The geometry is `WatchGlance`, and it is the height
/// that decides it — at 40 mm the petals keep 38 pt and the ring shrinks to
/// 46, which is what "shrink the ring, not the petals" costs.
///
/// ── ONE NUMBER IN THE MIDDLE ────────────────────────────────────────────────
/// Readiness, until the Crown lands on a petal; then that petal's reading, in
/// its ink. A thin battery arc runs inside the readiness ring. That is the
/// whole of the page's text — the petal's NAME is its glyph and its place.
///
/// ── THE CROWN MOVES THE HIGHLIGHT, A TAP OPENS THE DETAIL (D3) ──────────────
/// Six detents, −1 being readiness. A tap on a petal — or on the centre, for
/// the one the Crown is on — PUSHES that petal's detail screen
/// (`navigationDestination(for: PetalDetail.self)` on the root stack). The
/// centre with nothing highlighted opens the Pulse page, readiness's own.
struct GlanceView: View {

    @Environment(WatchModel.self) private var model
    /// Turns to the Pulse page — the `TabView` selection one level up.
    let openReadiness: () -> Void

    /// −1 is readiness; 0…5 the petals, in `PetalDetail` order.
    @State private var crown: Double = -1

    private var highlighted: PetalDetail? { PetalDetail(rawValue: Int(crown.rounded())) }

    var body: some View {
        // Once a minute, so the heart petal goes hollow when its reading ages
        // past `WatchHeart.freshFor` without anything else changing.
        TimelineView(.everyMinute) { tick in
            GeometryReader { geo in
                let layout = WatchGlance.layout(width: geo.size.width, height: geo.size.height)
                ZStack {
                    ring(layout)
                    centre(layout, now: tick.date)
                    ForEach(PetalDetail.allCases) { petal in
                        let o = layout.offset(petal.rawValue)
                        NavigationLink(value: petal) {
                            PetalDisc(
                                glyph: petal.glyph, ink: petal.ink(model.dashboardTiles),
                                reading: reading(petal, now: tick.date),
                                lit: highlighted == petal, size: layout.petal
                            )
                        }
                        .buttonStyle(.plain)
                        .offset(x: o.x, y: o.y)
                        .accessibilityLabel(petal.title)
                        .accessibilityValue(reading(petal, now: tick.date).spoken)
                        .accessibilityHint("Opens \(petal.title)")
                    }
                }
                .frame(width: layout.square, height: layout.square)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .focusable()
        .digitalCrownRotation(
            $crown, from: -1, through: Double(PetalDetail.allCases.count - 1), by: 1,
            sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true
        )
        .dimmedWhenLuminanceReduced()
        // A glance is when the heart petal is read: fetch what Health saved
        // since the last one (anchored — a no-op when nothing is new).
        .onAppear { model.vitals.refresh() }
    }

    private func reading(_ petal: PetalDetail, now: Date) -> PetalReading {
        petal.reading(model.dashboardTiles, heart: model.vitals.heart, now: now)
    }

    // MARK: - The ring

    private var score: Int? { model.dashboardTiles?.score }
    private var battery: Int? { model.dashboardTiles?.battery }

    private func ring(_ layout: WatchGlance.Layout) -> some View {
        let stroke = WatchGlance.ringStroke
        let inner = layout.ring - 2 * (stroke + WatchGlance.batteryInset) - WatchGlance.batteryStroke
        return ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: stroke)
                .frame(width: layout.ring - stroke, height: layout.ring - stroke)
            Circle()
                .trim(from: 0, to: max(0, min(1, Double(score ?? 0) / 100)))
                .stroke(OnyxInk.Themed.accent, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: layout.ring - stroke, height: layout.ring - stroke)
            // The battery, thin, inside: the one reading the ring is made of
            // that the day spends. Absent without a reading — no track, so an
            // unmeasured battery is not drawn as an empty one.
            if let battery {
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, Double(battery) / 100)))
                    .stroke(Color.onyx.battery(battery), style: StrokeStyle(lineWidth: WatchGlance.batteryStroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: max(0, inner), height: max(0, inner))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Readiness")
        .accessibilityValue((score.map { "\($0)" } ?? "not scored yet") + (battery.map { ", battery \($0) percent" } ?? ""))
    }

    /// Readiness, or the highlighted petal's reading in its ink. The biggest
    /// target on the page, and it opens what it shows.
    @ViewBuilder
    private func centre(_ layout: WatchGlance.Layout, now: Date) -> some View {
        let lit = highlighted.map { ($0, reading($0, now: now)) }
        let label = Text(lit?.1.value ?? score.map { "\($0)" } ?? "—")
            .font(WatchType.value)
            .foregroundStyle(lit?.0.ink(model.dashboardTiles) ?? WatchInk.primary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: layout.centre, height: layout.centre)
            .contentShape(Circle())
        if let lit {
            NavigationLink(value: lit.0) { label }
                .buttonStyle(.plain)
                .accessibilityLabel(lit.0.title)
                .accessibilityValue(lit.1.spoken)
        } else {
            Button {
                WKInterfaceDevice.current().play(.click)
                openReadiness()
            } label: { label }
            .buttonStyle(.plain)
            .accessibilityLabel("Readiness")
            .accessibilityValue(score.map { "\($0)" } ?? "not scored yet")
            .accessibilityHint("Opens Pulse")
        }
    }
}

/// One petal: a disc in its fixed ink, and what the reading says about it.
private struct PetalDisc: View {
    let glyph: String
    let ink: Color
    let reading: PetalReading
    let lit: Bool
    let size: Double

    var body: some View {
        ZStack {
            switch reading.state {
            case .none:
                // Hollow: nothing to read. No fill, so it cannot be mistaken
                // for a reading of zero.
                Circle().strokeBorder(ink.opacity(lit ? 0.9 : 0.5), lineWidth: 1)
            case .reading:
                Circle().fill(ink.opacity(lit ? 0.34 : 0.22))
            case .progress(let p):
                Circle().fill(ink.opacity(lit ? 0.34 : 0.12))
                Circle().stroke(ink.opacity(0.22), lineWidth: 3).padding(1.5)
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, p)))
                    .stroke(ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1.5)
            }
            Image(systemName: glyph)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(lit ? WatchInk.primary : ink)
        }
        .frame(width: size, height: size)
        .scaleEffect(lit ? 1.08 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 1), value: lit)
        .contentShape(Circle())
    }
}

/// A petal's reading: its state, the short figure the centre prints when
/// the Crown is on it, and the sentence VoiceOver says.
struct PetalReading: Equatable {
    enum State: Equatable {
        /// No reading — a hollow ring.
        case none
        /// A reading with no goal to fill toward — a filled disc, no arc.
        case reading
        /// A reading against a goal.
        case progress(Double)
    }
    let state: State
    /// Four glyphs at most: the centre is 30 pt across at 40 mm.
    let value: String
    let spoken: String
}

/// The six petals, and the six detail screens they open (D3) — one type,
/// because a petal IS its detail's door. In `WatchGlance.angles` order, which
/// is the Crown's order: sleep, water, food across the top; heart, steps,
/// stress across the bottom.
enum PetalDetail: Int, CaseIterable, Identifiable, Hashable {
    case sleep, water, food, heart, steps, stress

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .sleep: "Sleep"
        case .water: "Water"
        case .food: "Food"
        case .heart: "Heart"
        case .steps: "Steps"
        case .stress: "Stress"
        }
    }

    var glyph: String {
        switch self {
        case .sleep: "moon.fill"
        case .water: "drop.fill"
        case .food: "fork.knife"
        case .heart: "heart.fill"
        case .steps: "figure.walk"
        case .stress: "brain.head.profile"
        }
    }

    /// The fixed semantic inks (`OnyxInk.Fixed`), the dampened calories ink
    /// for food, the secondary ink for steps (a count with no domain of its
    /// own — the Body tab's call) and the stress band's own ink.
    func ink(_ t: WatchTiles?) -> Color {
        switch self {
        case .sleep: OnyxInk.Fixed.sleepREM
        case .water: OnyxInk.Fixed.water
        case .food: Color.onyx.calories
        case .heart: OnyxInk.Fixed.heart
        case .steps: WatchInk.secondary
        case .stress: WatchInk.stress(t?.stressIndex.map(Stress.band))
        }
    }

    /// Every figure is the phone's (`WatchTiles`) but the heart, which is the
    /// one reading only this wrist takes (`WatchVitals`).
    func reading(_ t: WatchTiles?, heart: LastHeartRate?, now: Date) -> PetalReading {
        switch self {
        case .sleep:
            guard let min = t?.sleepMin, min > 0 else { return .empty("no night recorded") }
            let text = OnyxSnapshot.formatSleep(min)
            return PetalReading(
                state: Self.state(Double(min), goal: t?.sleepGoalMin.map(Double.init)),
                value: "\(min / 60):" + String(format: "%02d", min % 60), spoken: text
            )
        case .water:
            guard let ml = t?.waterMl, ml > 0 else { return .empty("nothing logged") }
            let litres = String(format: "%.1f", Double(ml) / 1000)
            return PetalReading(
                state: Self.state(Double(ml), goal: t?.waterGoalMl.map(Double.init)),
                value: litres + "L", spoken: "\(litres) litres"
            )
        case .food:
            guard let kcal = t?.kcal, kcal > 0 else { return .empty("nothing logged") }
            return PetalReading(
                state: Self.state(Double(kcal), goal: t?.kcalGoal.map(Double.init)),
                value: Self.compact(kcal),
                spoken: "\(kcal) calories" + (t?.kcalRemaining.map { $0 >= 0 ? ", \($0) left" : ", \(-$0) over" } ?? "")
            )
        case .heart:
            guard let heart, WatchHeart.freshness(heart, now: now) == .fresh else {
                return .empty(heart == nil ? "no reading" : "no recent reading")
            }
            return PetalReading(state: .reading, value: "\(heart.bpm)", spoken: "\(heart.bpm) beats per minute")
        case .steps:
            guard let steps = t?.steps, steps > 0 else { return .empty("no steps yet") }
            return PetalReading(
                state: Self.state(Double(steps), goal: t?.stepsGoal.map(Double.init)),
                value: Self.compact(steps), spoken: "\(steps) steps"
            )
        case .stress:
            guard let index = t?.stressIndex else { return .empty("no reading") }
            let n = Int(index.rounded())
            return PetalReading(
                state: .progress(min(1, max(0, index / 100))), value: "\(n)",
                spoken: "index \(n), " + (Stress.bandLabel(Stress.band(index)) ?? Stress.band(index).rawValue)
            )
        }
    }

    private static func state(_ value: Double, goal: Double?) -> PetalReading.State {
        guard let goal, goal > 0 else { return .reading }
        return .progress(min(1, value / goal))
    }

    /// 8 412 → "8.4k", 640 → "640".
    static func compact(_ n: Int) -> String {
        n >= 1_000 ? String(format: "%.1fk", Double(n) / 1_000) : "\(n)"
    }
}

private extension PetalReading {
    static func empty(_ spoken: String) -> PetalReading { PetalReading(state: .none, value: "—", spoken: spoken) }
}
