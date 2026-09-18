import Foundation

// The Pulse tab's arrangement — the order of its six squares.
//
// The fourth key on `dashboard_layouts.layout`, beside `phone`, `desktop` and
// `train`, for every reason `TrainLayout`'s header gives: one row per user,
// already mirrored, already pushed through the outbox, and a `v` that is the
// SIDES gate and must not move. `pulse` is read and written independently of
// it; absent means the declaration order below, which is the order the grid
// shipped in.
//
// Unlike Train this IS an arrangement — the user drags squares — but it is
// still not a `DashboardLayout`: six fixed squares, one size, no stacking, no
// hiding. An ordered list of six names is the whole model.

/// One square of the Pulse grid. Declaration order is the default order and
/// the order `reconcile` appends a square a later wave adds.
public enum PulseSquare: String, Codable, Sendable, CaseIterable {
    case stress, stressLog, soreness, fatigue, scale, stack
}

/// The six squares in the order the reader put them, and when they last did.
public struct PulseLayout: Codable, Sendable, Equatable {
    public var order: [PulseSquare]
    /// Epoch ms of the last edit; 0 for an arrangement never written.
    public var updatedAt: Double

    public init(order: [PulseSquare] = PulseSquare.allCases, updatedAt: Double = 0) {
        self.order = Self.reconcile(order)
        self.updatedAt = updatedAt
    }

    public static let `default` = PulseLayout()

    /// Every square exactly once: duplicates dropped, missing ones appended in
    /// declaration order. Unknown names never reach this — `pulseLayout(from:)`
    /// drops them at the parse.
    public static func reconcile(_ order: [PulseSquare]) -> [PulseSquare] {
        var seen = Set<PulseSquare>()
        var out = order.filter { seen.insert($0).inserted }
        out += PulseSquare.allCases.filter { !seen.contains($0) }
        return out
    }

    /// `square` moved to `target`'s position, everything else closing up —
    /// the same verb `Dashboard.moveSlot` gives the grid. Stamped here, so
    /// `updatedAt` cannot lie about an edit that skipped the door.
    public func moving(_ square: PulseSquare, to target: PulseSquare) -> PulseLayout {
        guard square != target, let from = order.firstIndex(of: square),
              let to = order.firstIndex(of: target) else { return self }
        var out = order
        out.remove(at: from)
        out.insert(square, at: to)
        return PulseLayout(order: out, updatedAt: (Date().timeIntervalSince1970 * 1000).rounded(.down))
    }
}

public extension Dashboard {
    /// The sibling key on `dashboard_layouts.layout` that holds the above.
    static let pulseKey = "pulse"

    /// The Pulse arrangement inside a stored payload. Never throws; every
    /// shape that is not a readable `pulse` object is the default.
    static func pulseLayout(from stored: Any?) -> PulseLayout {
        guard let dict = stored as? [String: Any],
              let side = dict[pulseKey] as? [String: Any]
        else { return .default }
        let order = (side["order"] as? [Any])?
            .compactMap { ($0 as? String).flatMap(PulseSquare.init(rawValue:)) } ?? []
        let updatedAt: Double = {
            if let n = jsNumber(side["updatedAt"]), n.isFinite { return n }
            return 0
        }()
        return PulseLayout(order: order, updatedAt: updatedAt)
    }

    /// The stored payload with the Pulse arrangement replaced and everything
    /// else — both surfaces, the version, the train key — carried through byte
    /// for byte. The mirror of `withTrain`, for the same reason.
    static func withPulse(_ layout: PulseLayout, in stored: Any?) -> [String: Any] {
        var out = (stored as? [String: Any]) ?? [:]
        out[pulseKey] = [
            "order": layout.order.map(\.rawValue),
            "updatedAt": layout.updatedAt,
        ] as [String: Any]
        return out
    }
}
