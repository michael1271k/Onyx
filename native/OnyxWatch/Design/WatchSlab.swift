import OnyxUI
import SwiftUI

/// The watch's card — the "Stone" slab (overhaul A2, concept 1 + challenge C1).
///
/// ── WHAT IT IS ──────────────────────────────────────────────────────────────
/// A 16 pt continuous-corner slab: a `.thinMaterial` frost over the pure black
/// ground, washed with the page's ink at 8 %, a one-PIXEL highlight along its
/// top edge fading out by its middle, and no shadow. The phone's slab is the
/// same object at 20 pt; the watch's is smaller because its cards are.
///
/// ── WHY A MATERIAL AFTER `WatchInk` SPENT A PARAGRAPH AGAINST ONE ───────────
/// `WatchInk`'s header rules out glass on the LIVE screens — a blur pass per
/// frame inside an `HKWorkoutSession`. This slab is drawn only on the idle
/// dashboard, where the founder's challenge C1 asked for the frost by name
/// (content scrolling behind a slab frosts rather than sliding under a flat
/// fill), and where nothing is held under a bar for an hour.
///
/// ── THE INK IS THE PAGE'S, SET AS A HIERARCHY ───────────────────────────────
/// `foregroundStyle(tint, secondary)`, exactly the trick the old
/// `DashboardCard` used: `AccessoryFace` draws its glyph and headline with no
/// style of its own and its caption `.secondary`, so the page's ink lands on
/// the first two and the caption stays grey — without touching a face shared
/// with the phone's Lock Screen and the complications.
struct WatchSlab<Content: View>: View {

    /// The page's ink; nil draws a neutral slab.
    var tint: Color?
    @ViewBuilder var content: Content

    @Environment(\.displayScale) private var displayScale

    static var radius: CGFloat { 16 }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OnyxSpace.s)
            .padding(.vertical, 6)
            .foregroundStyle(tint ?? WatchInk.primary, WatchInk.secondary)
            .background {
                ZStack {
                    shape.fill(.thinMaterial)
                    shape.fill((tint ?? .white).opacity(0.08))
                }
            }
            .overlay {
                // One device pixel, whatever the scale — the top edge and the
                // shoulders of the corners, gone by the slab's middle.
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.12), .clear], startPoint: .top, endPoint: .center),
                    lineWidth: 1 / max(displayScale, 1)
                )
            }
    }
}
