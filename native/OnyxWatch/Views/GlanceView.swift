import OnyxCore
import OnyxUI
import SwiftUI
import WatchKit

/// Page one of the dashboard: readiness as a ring, and four petals around it
/// — sleep, water, food, vitals (overhaul A2, decision Q4, concept 4).
///
/// ── ZERO TEXT ON THE FIRST PAINT, ONE NUMBER IN THE MIDDLE ──────────────────
/// The ring is the day's verdict; the petals are the four things it is made
/// of, each in its own ink and each carrying its own progress arc. The centre
/// prints ONE reading: readiness until the Crown moves, then the petal the
/// Crown is on. That is the whole of the page's text.
///
/// ── THE CROWN MOVES THE HIGHLIGHT, A TAP OPENS THE PAGE ─────────────────────
/// Four detents, one per petal, with the system's detent haptic, plus a rest
/// position below the first that means "readiness". A tap on a petal — or on
/// the centre, for the one the Crown is on — opens that domain's page. The
/// page's Crown therefore does not page the dashboard; a swipe does, which is
/// the trade the founder took with decision Q4.
///
/// ── THE INKS ────────────────────────────────────────────────────────────────
/// The ring is the theme's accent — the one thing on the page the user chose.
/// The petals are the semantic inks that never follow a theme (`OnyxInk.Fixed`:
/// sleep lavender, water blue, heart red) and food the dampened calories ink,
/// so the four read the same in all eight themes.
struct GlanceView: View {

    @Environment(WatchModel.self) private var model
    /// Opens a dashboard page — the `TabView` selection one level up.
    let open: (DashboardPage) -> Void

    /// −1 is readiness; 0…3 the petals, in `Petal` order.
    @State private var crown: Double = -1

    private var highlighted: Petal? {
        let index = Int(crown.rounded())
        return Petal.allCases.indices.contains(index) ? Petal.allCases[index] : nil
    }

    var body: some View {
        GeometryReader { geo in
            let layout = WatchGlance.layout(width: geo.size.width, height: geo.size.height)
            ZStack {
                ring(layout)
                centre(layout)
                ForEach(Petal.allCases) { petal in
                    petalButton(petal, layout)
                        .offset(x: petal.corner.x * (layout.square - layout.petal) / 2,
                                y: petal.corner.y * (layout.square - layout.petal) / 2)
                }
            }
            .frame(width: layout.square, height: layout.square)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .focusable()
        .digitalCrownRotation(
            $crown, from: -1, through: Double(Petal.allCases.count - 1), by: 1,
            sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true
        )
        .dimmedWhenLuminanceReduced()
    }

    // MARK: - The ring

    private var score: Int? { model.dashboardTiles?.score }

    private func ring(_ layout: WatchGlance.Layout) -> some View {
        let progress = Double(score ?? 0) / 100
        return ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: WatchGlance.ringStroke)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(OnyxInk.Themed.accent, style: StrokeStyle(lineWidth: WatchGlance.ringStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: layout.ring - WatchGlance.ringStroke, height: layout.ring - WatchGlance.ringStroke)
        .accessibilityElement()
        .accessibilityLabel("Readiness")
        .accessibilityValue(score.map { "\($0)" } ?? "not scored yet")
    }

    /// Readiness, or the highlighted petal's reading. A button: the centre is
    /// the biggest target on the page, and it opens what it is showing.
    private func centre(_ layout: WatchGlance.Layout) -> some View {
        let reading = highlighted.map { $0.reading(model.dashboardTiles) }
        return Button {
            WKInterfaceDevice.current().play(.click)
            open(highlighted?.page ?? .pulse)
        } label: {
            VStack(spacing: 0) {
                Text(reading?.value ?? score.map { "\($0)" } ?? "—")
                    .font(highlighted == nil ? WatchType.figure : WatchType.value)
                    .foregroundStyle(WatchInk.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(highlighted?.title ?? "Readiness")
                    .font(WatchType.label)
                    .foregroundStyle(highlighted?.ink ?? WatchInk.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            // Inside the ring's stroke, with a margin — the digits never
            // touch the arc.
            .frame(width: (layout.ring - WatchGlance.ringStroke * 2) * 0.8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(highlighted?.title ?? "Readiness")
        .accessibilityValue(reading?.spoken ?? (score.map { "\($0)" } ?? "not scored yet"))
        .accessibilityHint("Opens \((highlighted?.page ?? .pulse).title)")
    }

    // MARK: - The petals

    private func petalButton(_ petal: Petal, _ layout: WatchGlance.Layout) -> some View {
        let reading = petal.reading(model.dashboardTiles)
        let lit = highlighted == petal
        return Button {
            WKInterfaceDevice.current().play(.click)
            open(petal.page)
        } label: {
            ZStack {
                Circle().fill(petal.ink.opacity(lit ? 0.34 : 0.16))
                if let progress = reading.progress {
                    Circle()
                        .trim(from: 0, to: max(0.02, min(1, progress)))
                        .stroke(petal.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1.5)
                } else {
                    Circle().strokeBorder(petal.ink.opacity(0.5), lineWidth: 1)
                }
                Image(systemName: petal.glyph)
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(lit ? WatchInk.primary : petal.ink)
            }
            .frame(width: layout.petal, height: layout.petal)
            .scaleEffect(lit ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(petal.title)
        .accessibilityValue(reading.spoken)
        .accessibilityHint("Opens \(petal.page.title)")
    }
}

/// The four petals, in Crown order — clockwise from the top left.
enum Petal: Int, CaseIterable, Identifiable {
    case sleep, water, food, vitals

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .sleep: "Sleep"
        case .water: "Water"
        case .food: "Food"
        case .vitals: "Heart"
        }
    }

    var glyph: String {
        switch self {
        case .sleep: "moon.fill"
        case .water: "drop.fill"
        case .food: "fork.knife"
        case .vitals: "heart.fill"
        }
    }

    /// The fixed semantic inks (`OnyxInk.Fixed`), and the dampened calories
    /// ink for food — see `GlanceView`'s header.
    var ink: Color {
        switch self {
        case .sleep: OnyxInk.Fixed.sleepREM
        case .water: OnyxInk.Fixed.water
        case .food: Color.onyx.calories
        case .vitals: OnyxInk.Fixed.heart
        }
    }

    var page: DashboardPage {
        switch self {
        case .sleep: .today
        case .water, .food: .fuel
        case .vitals: .pulse
        }
    }

    /// Which corner, as a unit offset from the centre.
    var corner: (x: Double, y: Double) {
        switch self {
        case .sleep: (-1, -1)
        case .water: (1, -1)
        case .food: (1, 1)
        case .vitals: (-1, 1)
        }
    }

    struct Reading {
        let value: String
        let spoken: String
        let progress: Double?
    }

    /// Every figure comes off `WatchTiles` (the phone's) except the heart,
    /// which is the one reading only this wrist takes (`LastHeartRate`).
    func reading(_ t: WatchTiles?) -> Reading {
        switch self {
        case .sleep:
            let text = t?.sleepMin.map(OnyxSnapshot.formatSleep) ?? "—"
            return Reading(value: text, spoken: t?.sleepMin == nil ? "no reading" : text,
                           progress: t?.sleepScore.map { Double($0) / 100 })
        case .water:
            let text = t?.waterMl.map { String(format: "%.1f L", Double($0) / 1000) } ?? "—"
            return Reading(value: text, spoken: t?.waterMl.map { "\($0) millilitres" } ?? "no reading",
                           progress: WatchTiles.progress(t?.waterMl, t?.waterGoalMl))
        case .food:
            let text = t?.kcalRemaining.map { "\($0) left" } ?? t?.kcal.map { "\($0) kcal" } ?? "—"
            return Reading(value: text, spoken: text == "—" ? "no reading" : text,
                           progress: WatchTiles.progress(t?.kcal, t?.kcalGoal))
        case .vitals:
            let bpm = LastHeartRate.load()?.bpm
            return Reading(value: bpm.map { "\($0)" } ?? "—",
                           spoken: bpm.map { "\($0) beats per minute" } ?? "no reading", progress: nil)
        }
    }
}
