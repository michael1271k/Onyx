import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

// ─────────────────────────────────────────────────────────────────────────────
// STRESS INDEX v1 on Pulse (§U5.3) — the tile, and the sheet behind it.
//
// The model is `docs/STRESS_MODEL.md`; the arithmetic is `OnyxCore.Stress` and
// `StressSeries`, replayed by the `stress-*` golden vectors. Nothing in this
// file computes anything: it draws one number, its band word, its fortnight and
// the four terms behind it.
//
// REPORT-ONLY (founder decision 2). The index is not a battery input and moves
// no score, which is why it sits below the Now strip rather than in it — and
// why the sheet says so in one line rather than leaving the reader to wonder
// why a "High" day still scored 78.
//
// ── WHERE THE TILE WENT (W3) ────────────────────────────────────────────────
// The reading is now `StressSquare`, one of the four in `PulseSquareGrid`. A
// full-width tile for one integer, one word and a 96 pt trace was a third of
// the compaction this screen owed, and the square holds all three. What is left
// in this file is the ink and the term order — both read by the square and by
// the breakdown sheet — and the sheet itself.
// ─────────────────────────────────────────────────────────────────────────────

extension StressBand {
    /// The band, in ink.
    ///
    /// ── WHY BASELINE IS TEXT AND NOT A HUE ──────────────────────────────────
    /// 50 is YOUR normal, and a colour on it would make "you are exactly
    /// average for you" a verdict. Same rule `Color.onyx.verdict` follows for
    /// `.neutral`, and the same reason the battery's own band is grey when it
    /// has no reading. Calm earns `good`; the two loaded bands take Solar's two
    /// stops before `danger`, which is the ramp `Color.onyx.battery` already
    /// walks in the other direction.
    var tint: Color {
        switch self {
        case .calm:        Color.onyx.good
        case .baseline:    Color.onyx.textPrimary
        case .elevated:    OnyxDomain.fuel.start
        case .high:        OnyxDomain.fuel.end
        case .overreached: Color.onyx.danger
        }
    }

    var word: String { Stress.bandLabel(self) ?? rawValue.capitalized }
}

extension StressTermKey {
    /// ── THE ORDER THE MODEL STATES THEM IN ──────────────────────────────────
    /// NOT `allCases`. The enum lists `auto, sleep, load` and then `selfReport`,
    /// because `self` is a keyword and its case had to be declared last — so
    /// `allCases` puts the 0.15 term above a 0.25 one and disagrees with both
    /// `STRESS_MODEL.md`'s table and the order `Stress.breakdown` sums in.
    /// Weights descending, as the document reads.
    static let display: [StressTermKey] = [.auto, .sleep, .selfReport, .load]

    /// The term in a sentence. `self` is the JSON key and "Self" is not a word
    /// anyone reads as a heading.
    var title: String {
        switch self {
        case .auto:       "Autonomic"
        case .sleep:      "Sleep"
        case .selfReport: "Self-report"
        case .load:       "Load"
        }
    }

    /// What the term is built from, for the row's second line.
    var source: String {
        switch self {
        case .auto:       "HRV and resting heart rate against your own baseline"
        case .sleep:      "How broken the night was, and whether it was hard to fall into"
        case .selfReport: "The mean of what you said today — the fatigue slots and the stress log"
        case .load:       "Acute:chronic ratio and this week's strain — never negative"
        }
    }
}

// MARK: - The breakdown

/// Where the number came from: four terms, their weights, and what answered
/// them (§U5.3).
///
/// ── WHY A DIVERGING BAR AND NOT FOUR NUMBERS ────────────────────────────────
/// Every term is a z-score on the SAME ±2 scale, and the only two things a
/// reader wants are which way each one pushed and how hard. Four signed
/// decimals make that a subtraction problem; four bars off one centre line make
/// it a glance. The weight is a caption rather than a second bar length —
/// `weightSum` renormalises over the ANSWERED terms, so the share printed here
/// is the share that actually built today's number, not the constant.
struct StressBreakdownSheet: View {
    let model: DayModel

    private var breakdown: Stress.Breakdown? { model.stressBreakdown }

    var body: some View {
        DaySheet("Stress", domain: .recover, glass: false, detents: [.large]) {
            Form {
                headlineSection
                if let breakdown, breakdown.index != nil {
                    termsSection(breakdown)
                }
                Section {
                    Text("The index is report-only. It changes no score and no battery percentage — it reads the same signals the battery does, arranged around a different question: how far from your own normal today sits.")
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textSecondary)
                } header: {
                    OnyxSectionHeader("What it does not do", .recover)
                }
            }
        }
    }

    private var headlineSection: some View {
        Section {
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
                    Text(breakdown?.index.map { "\(Int($0))" } ?? "—")
                        // `.display`, not `.clock` (W11). `.clock` is 34 pt and its own header
                        // says what it is for: a RUNNING clock, read across a gym floor while
                        // you decide whether to start the next set. A report-only index on a
                        // sheet is read at the distance everything else on it is, and at 34 pt
                        // it set the band word beside it two whole steps down the scale.
                        .onyxType(.display).onyxNumeral()
                        .foregroundStyle(breakdown?.band?.tint ?? Color.onyx.textSecondary)
                    Text(breakdown?.band.map(\.word) ?? "No reading")
                        .onyxType(.display)
                        .foregroundStyle(Color.onyx.textPrimary)
                    Spacer(minLength: 0)
                }
                Text(scale)
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textSecondary)
            }
            .padding(.vertical, OnyxSpace.xs)
            .accessibilityElement(children: .combine)
        } footer: {
            Text("Calm under 30 · Baseline to 50 · Elevated to 62 · High to 75 · Overreached above. 50 is your own normal, not a population's.")
        }
    }

    private var scale: String {
        guard let breakdown, breakdown.index != nil else {
            return "Nothing answered today — no heart-rate baseline, no night, no fatigue logged and no load."
        }
        let answered = StressTermKey.display.filter { breakdown.terms.z($0) != nil }
        return answered.count == StressTermKey.display.count
            ? "All four terms answered."
            : "\(answered.count) of 4 terms answered — the rest are renormalised away, not read as zero."
    }

    private func termsSection(_ breakdown: Stress.Breakdown) -> some View {
        Section {
            ForEach(StressTermKey.display, id: \.self) { key in
                TermRow(key: key, breakdown: breakdown)
            }
        } header: {
            OnyxSectionHeader("The four terms", .recover)
        } footer: {
            // ── THE SIGN CONVENTION, SAID ONCE ──────────────────────────────
            // Every figure in this section is a CONTRIBUTION TO STRESS, not a
            // reading: the model enters HRV negated (`-hrvZ`), so the "+1.1"
            // beside HRV means a suppressed HRV pushed the index up, and read
            // as a raw HRV delta it says the opposite. Stating the convention
            // once is cheaper and more honest than re-labelling four rows.
            Text("Every figure here is a push on the index, not a reading: plus is more stress. A suppressed HRV therefore scores positive, and load never scores below zero.")
        }
    }
}

/// One term: its name, its z as a diverging bar, its renormalised share, and
/// the pieces it was built from.
private struct TermRow: View {
    let key: StressTermKey
    let breakdown: Stress.Breakdown

    private var z: Double? { breakdown.terms.z(key) }

    private var weight: Double {
        switch key {
        case .auto:       breakdown.terms.auto.weight
        case .sleep:      breakdown.terms.sleep.weight
        case .selfReport: breakdown.terms.selfReport.weight
        case .load:       breakdown.terms.load.weight
        }
    }

    /// The share of the composite this term actually carried. `weightSum` is
    /// the sum over the ANSWERED terms, so an unanswered neighbour makes this
    /// larger than the constant — which is the renormalisation, made visible.
    private var share: String? {
        guard z != nil, breakdown.weightSum > 0 else { return nil }
        return "\(Int((weight / breakdown.weightSum * 100).rounded()))% of today"
    }

    /// What answered it, in this term's own units.
    private var pieces: String {
        switch key {
        case .auto:
            let t = breakdown.terms.auto
            return [t.hrv.map { "HRV \(signed($0))" }, t.rhr.map { "resting HR \(signed($0))" }]
                .compactMap { $0 }.joined(separator: " · ")
        case .sleep:
            let t = breakdown.terms.sleep
            return [
                t.frag.map { "fragmentation \(signed($0))" },
                t.onset.map { $0 > 0 ? "hard to fall asleep" : "fell asleep normally" },
            ].compactMap { $0 }.joined(separator: " · ")
        case .selfReport:
            // Two self-reports, averaged over whichever answered (D6). Naming
            // only the one that did is what stops "fatigue 2.0 of 5" reading as
            // the whole term on a day the stress log also spoke.
            let t = breakdown.terms.selfReport
            return [
                t.fatigueDayMean.map { "fatigue \(jsToFixed($0, 1)) of 5" },
                t.stressDayMean.map { "head \(jsToFixed($0, 1)) of 5" },
            ].compactMap { $0 }.joined(separator: " · ")
        case .load:
            let t = breakdown.terms.load
            guard t.answered > 0 else { return "" }
            return "acute:chronic \(signed(t.acwrTerm)) · strain \(signed(t.strainTerm))"
        }
    }

    private func signed(_ v: Double) -> String {
        "\(v > 0 ? "+" : v < 0 ? "−" : "")\(jsToFixed(abs(v), 1))"
    }

    /// Which way it pushed. `neutral` — exactly zero — is text ink, because "it
    /// did not move" is a statement rather than a verdict (`Color.onyx.verdict`
    /// makes the same choice inside a maintenance band).
    private var tint: Color {
        guard let z, z != 0 else { return Color.onyx.textSecondary }
        return z > 0 ? (breakdown.band?.tint ?? Color.onyx.danger) : Color.onyx.good
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.xs) {
            HStack(spacing: OnyxSpace.s) {
                Text(key.title)
                    .onyxType(.body)
                    .foregroundStyle(Color.onyx.textPrimary)
                Spacer(minLength: OnyxSpace.s)
                Text(z.map(signed) ?? "not answered")
                    .onyxType(.caption).fontWeight(.semibold).onyxNumeral()
                    .foregroundStyle(z == nil ? Color.onyx.textTertiary : tint)
            }
            if let z {
                DivergingBar(value: z, extent: Readiness.constants.zClamp, tint: tint)
                    .frame(height: 6)
            }
            Text([share, pieces.isEmpty ? nil : pieces].compactMap { $0 }.joined(separator: " · "))
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if z == nil {
                Text(key.source)
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, OnyxSpace.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(key.title)
        .accessibilityValue(z.map { "\(signed($0)), \(share ?? "")\(pieces.isEmpty ? "" : ". \(pieces)")" }
                            ?? "not answered. \(key.source)")
    }
}

// `DivergingBar` moved to OnyxUI in W6 — the Deficit tile draws seven of them
// and a second centred bar would be a second set of decisions about what a
// zero-length one looks like. It is imported with the rest of the package.
