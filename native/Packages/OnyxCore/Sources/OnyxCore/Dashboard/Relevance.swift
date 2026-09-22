import Foundation

/// Today's card order, by the clock (§W6-B.3).
///
/// ── ORDERING IS NOT HIDING ──────────────────────────────────────────────────
/// Decision 25 forbids hide-until-data and decision 24 forbids solving bloat by
/// putting things away. So nothing here removes a card, changes a size or
/// touches `hidden`: the same slots come back in a different order, and every
/// one of them is on the same page it was on before. What moves is the HERO —
/// which card you land on — and it moves because at 07:00 the question is how
/// you slept and at 20:00 it is what you have eaten.
///
/// ── AND IT YIELDS TO THE USER, ALWAYS ───────────────────────────────────────
/// `DashboardLayout.updatedAt` is 0 for a layout nobody has ever arranged
/// (`Layout.swift`), and the first drag, resize, stack or hide writes a real
/// timestamp. That is the pin: the moment this person has said what order they
/// want, this function returns their layout untouched, forever. A ranking that
/// could re-order a grid somebody built by hand would be a bug they could not
/// even report — the cards would simply be somewhere else each time they
/// looked.
public extension Dashboard {

    /// The bands, in local minutes from midnight. A band is a claim about what
    /// somebody opens their phone to ask, not about what time it is: 04:00 is
    /// morning because the person reading a sleep score at 04:40 has just woken
    /// up, and 17:00 is evening because that is when the day's eating becomes a
    /// question you can still answer.
    enum Band: Sendable, Equatable {
        case morning, midday, evening

        public static func at(_ minuteOfDay: Int) -> Band {
            switch minuteOfDay {
            case (4 * 60)..<(12 * 60): return .morning
            case (17 * 60)..<(24 * 60): return .evening
            default: return .midday
            }
        }

        /// The cards this band leads with, best first. Everything not named
        /// keeps its own order behind them.
        var leads: [WidgetId] {
            switch self {
            // How you slept, what it did to you, and what that means for the
            // session in front of you.
            case .morning: return [.sleep, .recovery, .train]
            // Nothing is a better answer than anything else in the middle of
            // the day, and moving the cards at noon for no reason is worse
            // than leaving them.
            case .midday: return []
            // What is left to eat and drink, and what tomorrow asks for.
            case .evening: return [.fuel, .water, .train]
            }
        }
    }

    /// `layout`, with its slots ranked for the clock — or `layout` itself when
    /// the user has arranged it.
    static func relevanceOrdered(_ layout: DashboardLayout, minuteOfDay: Int) -> DashboardLayout {
        guard layout.updatedAt == 0 else { return layout }
        let leads = Band.at(minuteOfDay).leads
        guard !leads.isEmpty else { return layout }
        var rankOf: [WidgetId: Int] = [:]
        for (index, id) in leads.enumerated() { rankOf[id] = index }

        // A slot is ranked by the BEST card in it: a stack holding sleep and
        // steps leads a morning, because the reason you are looking at that
        // slot is the sleep face. Unranked slots sort behind every ranked one
        // and keep their stored order among themselves — `enumerated` plus a
        // tuple comparison is a stable sort, which `sorted(by:)` is not.
        let ranked = layout.slots.enumerated().map { position, slot -> (rank: Int, position: Int, slot: StackSlot) in
            let best = slot.items.compactMap { rankOf[$0] }.min() ?? leads.count
            return (best, position, slot)
        }
        var out = layout
        out.slots = ranked
            .sorted { ($0.rank, $0.position) < ($1.rank, $1.position) }
            .map(\.slot)
        return out
    }
}
