import SwiftUI
import OnyxUI
import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// The Body tab's hero (Precision B4, decisions Q19 + Q22 · design 9): one
// instrument — the readiness ring with a thin inner battery arc, orbited by six
// petals (Sleep · Water · Food on the top arc, Heart · Steps · Stress on the
// bottom), each a 44 pt disc with its own progress arc in its FIXED ink.
//
// It replaces the Now strip (score, battery and the fuel sentence ARE the ring
// and three of its petals) and it is the screen's ONE `.hero`: the score.
//
// A petal with nothing to say is a hollow ring with no caption — never "—".
// A petal with a reading but no goal (steps before a target exists) is a
// filled disc with its value and no arc: an arc against a goal nobody set is a
// number nobody asked for (the same rule `sleepDebt` states).
// ─────────────────────────────────────────────────────────────────────────────

/// The ring's geometry, local to the phone (seam 5): W-final may swap it for
/// Lane D's six-petal `WatchGlance` if the two agree; a phone and a wrist have
/// different room, so both may stay.
enum BodyRingLayout {
    /// The readiness ring's diameter.
    static let ring: CGFloat = 200
    static let ringStroke: CGFloat = 14
    /// The battery arc, inside the ring.
    static let batteryStroke: CGFloat = 4
    static let batteryInset: CGFloat = 10
    static let petal: CGFloat = 44
    static let petalStroke: CGFloat = 3
    /// Ring edge to petal edge.
    static let gap: CGFloat = 8
    /// One caption line's band beside a petal.
    static let caption: CGFloat = 18

    /// The petal centres' distance from the ring's centre.
    static var orbit: CGFloat { ring / 2 + gap + petal / 2 }

    /// Six petals evenly spaced, 60° apart, none on the horizontal axis —
    /// three over the ring, three under it. Degrees, screen space (y down):
    /// top-left, top, top-right, then bottom-left, bottom, bottom-right.
    static let angles: [Double] = [-150, -90, -30, 150, 90, 30]

    /// A petal's centre as an offset from the ring's centre.
    nonisolated static func offset(_ index: Int) -> CGSize {
        let a = angles[index] * .pi / 180
        return CGSize(width: orbit * cos(a), height: orbit * sin(a))
    }

    /// The whole instrument's frame: the orbit, a petal's radius and a
    /// caption band on each side, vertically; the side petals' captions
    /// horizontally.
    static var size: CGSize {
        let side = orbit * cos(30 * .pi / 180) + petal / 2 + 12
        return CGSize(width: side * 2, height: (orbit + petal / 2 + caption + 6) * 2)
    }
}

/// One petal's reading.
struct BodyPetal: Identifiable, Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case sleep, water, food, heart, steps, stress
        var id: String { rawValue }

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

        var symbol: String {
            switch self {
            case .sleep: "moon.zzz.fill"
            case .water: "drop.fill"
            case .food: "fork.knife"
            case .heart: "heart.fill"
            case .steps: "figure.walk"
            case .stress: "waveform.path"
            }
        }
    }

    let kind: Kind
    /// 0…1 against its goal; nil = no goal (a reading drawn without an arc).
    let fraction: Double?
    /// The caption; nil = no data (a hollow ring and no caption).
    let value: String?
    let ink: Color
    /// What VoiceOver says after the title.
    let spoken: String

    var id: String { kind.rawValue }
}

extension DayModel {
    /// The six petals, in `BodyRingLayout.angles` order.
    var bodyPetals: [BodyPetal] {
        let targets = dayTargets
        return [sleepPetal(targets), waterPetal(targets), foodPetal(targets),
                heartPetal, stepsPetal(targets), stressPetal]
    }

    private func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }

    private func sleepPetal(_ t: ResolvedTargets) -> BodyPetal {
        let ink = OnyxInk.Fixed.sleepREM
        guard let minutes = night.flatMap({ $0.durationMin > 0 ? Double($0.durationMin) : nil }) else {
            return BodyPetal(kind: .sleep, fraction: nil, value: nil, ink: ink, spoken: "no night recorded")
        }
        let goal = (t.sleepHours ?? sleepGoalHours) * 60
        let fraction = goal > 0 ? clamp(minutes / goal) : nil
        return BodyPetal(kind: .sleep, fraction: fraction, value: Format.sleep(minutes), ink: ink,
                         spoken: Format.sleep(minutes) + (fraction.map { ", \(Int(($0 * 100).rounded())) percent of goal" } ?? ""))
    }

    private func waterPetal(_ t: ResolvedTargets) -> BodyPetal {
        let ink = OnyxInk.Fixed.water
        guard let ml = waterMl, ml > 0 else {
            return BodyPetal(kind: .water, fraction: nil, value: nil, ink: ink, spoken: "nothing logged")
        }
        let fraction = (t.waterMl ?? 0) > 0 ? clamp(ml / t.waterMl!) : nil
        let litres = "\(DayFormat.number(ml / 1000)) L"
        return BodyPetal(kind: .water, fraction: fraction, value: litres, ink: ink,
                         spoken: litres + (fraction.map { ", \(Int(($0 * 100).rounded())) percent of goal" } ?? ""))
    }

    private func foodPetal(_ t: ResolvedTargets) -> BodyPetal {
        let ink = Color.onyx.calories
        guard let kcal = kcalEaten else {
            return BodyPetal(kind: .food, fraction: nil, value: nil, ink: ink, spoken: "nothing logged")
        }
        let fraction = t.kcal > 0 ? clamp(kcal / t.kcal) : nil
        let text = NutritionFormat.whole(kcal)
        return BodyPetal(kind: .food, fraction: fraction, value: text + " kcal", ink: ink,
                         spoken: "\(text) calories" + (t.kcal > 0 ? " of \(NutritionFormat.whole(t.kcal))" : ""))
    }

    /// Full at or under the fortnight's resting heart rate, a tenth less per
    /// beat above it: a raised resting rate is the heart's own "not yet".
    private var heartPetal: BodyPetal {
        let ink = OnyxInk.Fixed.heart
        guard let bpm = window.vitals.restingBpm?.value else {
            return BodyPetal(kind: .heart, fraction: nil, value: nil, ink: ink, spoken: "no resting heart rate")
        }
        let fraction = window.vitals.restingBpm?.baseline.map { clamp(1 - (bpm - $0) / 10) }
        let text = "\(Int(bpm.rounded()))"
        return BodyPetal(kind: .heart, fraction: fraction, value: text + " bpm", ink: ink,
                         spoken: "resting \(text) beats per minute")
    }

    private func stepsPetal(_ t: ResolvedTargets) -> BodyPetal {
        let ink = Color.onyx.textSecondary
        guard let steps = window.steps?.value, steps > 0 else {
            return BodyPetal(kind: .steps, fraction: nil, value: nil, ink: ink, spoken: "no steps yet")
        }
        let fraction = (t.steps ?? 0) > 0 ? clamp(steps / t.steps!) : nil
        let text = steps >= 10_000 ? "\(DayFormat.number(steps / 1000))k" : NutritionFormat.whole(steps)
        return BodyPetal(kind: .steps, fraction: fraction, value: text, ink: ink,
                         spoken: "\(NutritionFormat.whole(steps)) steps" + (fraction.map { ", \(Int(($0 * 100).rounded())) percent of goal" } ?? ""))
    }

    /// The index, 10–90, as a share of 100 in its band's own ink.
    private var stressPetal: BodyPetal {
        guard let day = stress, let index = day.index else {
            return BodyPetal(kind: .stress, fraction: nil, value: nil, ink: Color.onyx.textSecondary, spoken: "no reading")
        }
        let text = "\(Int(index.rounded()))"
        return BodyPetal(kind: .stress, fraction: clamp(index / 100), value: text,
                         ink: day.band?.tint ?? Color.onyx.textSecondary,
                         spoken: "index \(text)" + (day.band.map { ", \($0.rawValue)" } ?? ""))
    }
}

/// The instrument.
struct BodyRing: View {
    let score: Int?
    let battery: Int?
    let petals: [BodyPetal]
    let onPetal: (BodyPetal.Kind) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let size = BodyRingLayout.size
        ZStack {
            readiness
            ForEach(Array(petals.enumerated()), id: \.element.id) { index, petal in
                let offset = BodyRingLayout.offset(index)
                PetalView(petal: petal, captionAbove: offset.height < 0) { onPetal(petal.kind) }
                    .offset(offset)
            }
        }
        .frame(width: size.width, height: size.height)
        .frame(maxWidth: .infinity)
        // The instrument is geometry: past accessibility1 its captions and the
        // numeral would outgrow the orbit (the brief's cap).
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// The ring, the battery arc inside it, and the score.
    private var readiness: some View {
        let accent = OnyxInk.Themed.accent
        let d = BodyRingLayout.ring
        let inner = d - BodyRingLayout.ringStroke * 2 - BodyRingLayout.batteryInset * 2
        return ZStack {
            Circle()
                .stroke(Color.onyx.hairline, lineWidth: BodyRingLayout.ringStroke)
            Circle()
                .trim(from: 0, to: Double(score ?? 0) / 100)
                .stroke(accent, style: StrokeStyle(lineWidth: BodyRingLayout.ringStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .stroke(Color.onyx.hairline, lineWidth: BodyRingLayout.batteryStroke)
                .frame(width: inner, height: inner)
            Circle()
                .trim(from: 0, to: Double(battery ?? 0) / 100)
                .stroke(Color.onyx.battery(battery), style: StrokeStyle(lineWidth: BodyRingLayout.batteryStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: inner, height: inner)
            VStack(spacing: 2) {
                if let score {
                    Text("\(score)")
                        .onyxType(.hero).onyxNumeral()
                        .foregroundStyle(Color.onyx.textPrimary)
                } else {
                    Text("Not scored")
                        .onyxType(.secondary).fontWeight(.semibold)
                        .foregroundStyle(Color.onyx.textSecondary)
                }
                Text("READINESS").onyxMicro()
                if let battery {
                    Text("Battery \(battery)")
                        .onyxType(.caption).onyxNumeral().fontWeight(.semibold)
                        .foregroundStyle(Color.onyx.battery(battery))
                        .padding(.top, OnyxSpace.xs)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: inner - 24)
            // The words inside the ring stop a step before the petals do: at
            // accessibility1 "Battery 64" ran over the inner arc (critique).
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .frame(width: d, height: d)
        .animation(reduceMotion ? nil : OnyxMotion.counter, value: score)
        .animation(reduceMotion ? nil : OnyxMotion.counter, value: battery)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Readiness \(score.map { "\($0)" } ?? "not scored"), battery \(battery.map { "\($0) percent" } ?? "unknown")")
    }
}

/// One petal: a disc, its arc, its glyph, and its value on the outer side.
private struct PetalView: View {
    let petal: BodyPetal
    /// Top-arc petals caption above, bottom-arc below — always AWAY from the
    /// ring, never across it.
    let captionAbove: Bool
    let action: () -> Void

    private var hasData: Bool { petal.value != nil }

    var body: some View {
        Button(action: action) {
            ZStack {
                disc
                caption
                    .offset(y: (captionAbove ? -1 : 1) * (BodyRingLayout.petal / 2 + BodyRingLayout.caption / 2 + 2))
            }
            .frame(width: BodyRingLayout.petal, height: BodyRingLayout.petal)
            .contentShape(Circle())
        }
        .buttonStyle(OnyxPressStyle(scale: 0.92))
        .accessibilityLabel(petal.kind.title)
        .accessibilityValue(petal.spoken)
        .accessibilityHint("Opens \(petal.kind.title.lowercased())")
    }

    private var disc: some View {
        let s = BodyRingLayout.petalStroke
        return ZStack {
            if hasData {
                Circle().fill(petal.ink.opacity(petal.fraction == nil ? 0.22 : 0.12))
                Circle().stroke(petal.ink.opacity(0.22), lineWidth: s)
                if let fraction = petal.fraction {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(petal.ink, style: StrokeStyle(lineWidth: s, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            } else {
                // Hollow: the ring is the whole statement.
                Circle().stroke(Color.onyx.textTertiary, lineWidth: s / 2)
            }
            Image(systemName: petal.kind.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(hasData ? petal.ink : Color.onyx.textTertiary)
        }
        .frame(width: BodyRingLayout.petal, height: BodyRingLayout.petal)
    }

    @ViewBuilder
    private var caption: some View {
        if let value = petal.value {
            Text(value)
                .onyxType(.caption).onyxNumeral().fontWeight(.semibold)
                .foregroundStyle(Color.onyx.textPrimary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}
