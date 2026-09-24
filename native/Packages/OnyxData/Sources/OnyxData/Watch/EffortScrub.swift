import Foundation

/// The Crown scrubbing an RPE ladder, turned into two signals (overhaul A3,
/// decision Q2).
///
/// ── WHY TWO CLOCKS ──────────────────────────────────────────────────────────
/// The rest cover used to AMEND the set on every detent: scrubbing five rungs
/// wrote five permanent events into a log that is never compacted and queued
/// five transfers. Now a detent does two cheap things:
///
///   · `pulse` — 150 ms after the Crown stops moving, the rung it rests on
///     goes to the phone as an `EffortPulse` message (provisional ink on the
///     deck card, never stored). Fast enough to feel live, slow enough that a
///     spin across the ladder is one message, not eight.
///   · `settle` — ONE second of stillness is the end of the scrub, and only
///     then is the rating written, once. `flush()` settles at once — the cover
///     going away mid-scrub must not lose the rating the person chose.
///
/// A class on the main actor because the Crown's `onChange` is, and both
/// callbacks touch the model. Tested in OnyxDataTests with real (short) delays.
@MainActor
public final class EffortScrub {
    private let pulseDelay: Duration
    private let settleDelay: Duration
    private let onPulse: (Double) -> Void
    private let onSettle: (Double) -> Void
    private var pulseTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var pending: Double?

    public init(pulseDelay: Duration = .milliseconds(150), settleDelay: Duration = .seconds(1),
                pulse: @escaping (Double) -> Void, settle: @escaping (Double) -> Void) {
        self.pulseDelay = pulseDelay
        self.settleDelay = settleDelay
        self.onPulse = pulse
        self.onSettle = settle
    }

    /// The Crown landed on `rpe`. Restarts both clocks.
    public func scrub(_ rpe: Double) {
        pending = rpe
        pulseTask?.cancel()
        settleTask?.cancel()
        pulseTask = Task { [weak self, pulseDelay] in
            try? await Task.sleep(for: pulseDelay)
            guard !Task.isCancelled else { return }
            self?.onPulse(rpe)
        }
        settleTask = Task { [weak self, settleDelay] in
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled else { return }
            self?.settleNow()
        }
    }

    /// Settle whatever is pending, now. A no-op with nothing pending.
    public func flush() {
        settleTask?.cancel()
        // A provisional pulse arriving after the rating is written would
        // repaint the phone's capsule over a committed set.
        pulseTask?.cancel()
        settleNow()
    }

    private func settleNow() {
        guard let value = pending else { return }
        pending = nil
        onSettle(value)
    }
}
