import SwiftUI
import OnyxCore

// MARK: - Session Replay, drawn (overhaul W5, feature 2)
//
// ONE drawing of a `SessionReplay.Frame`, for every surface that plays one: the
// phone's summary card, the watch's three-second replay, the two share PNGs and
// every frame of the MP4. It draws what the frame says and decides nothing —
// timing lives in `SessionReplay` (OnyxCore), where the tests are.
//
// Inks: the trace is `OnyxInk.Fixed.heart` in every theme (decision Q19); a set
// is the theme accent (the athlete's own colour); a record is `record` gold;
// a movement is its primary mover's FIXED anatomical colour (Q18).
//
// A `Canvas` and not shapes: the MP4 redraws this 300 times, and one drawing
// pass over ~60 points and a dozen dots is the cheapest thing `ImageRenderer`
// can be handed. Cross-platform (no iOS-only type) — the watch draws it too.

public extension SessionReplay.Timeline {
    /// A movement's ink: its primary mover's fixed anatomical colour. A
    /// movement `MuscleMap` cannot place — a treadmill — takes the cardio ink,
    /// the answer the session page's chips already give.
    func ink(_ movement: Int) -> Color {
        guard movements.indices.contains(movement),
              let muscle = MuscleMap.primaryLandmarks(movements[movement].name).first
        else { return Color.onyx.cardio }
        return OnyxInk.Fixed.muscle(muscle)
    }
}

public struct ReplayCanvas: View {
    let timeline: SessionReplay.Timeline
    let frame: SessionReplay.Frame
    let accent: Color
    /// The trace's stroke; everything else scales from it, so the watch and a
    /// 1080 px share frame are the same drawing at two sizes.
    let lineWidth: CGFloat
    /// The surface under the canvas — each dot is cut out of the trace with
    /// a ring of it, so the ring must BE that surface, not black.
    let ground: Color

    public init(timeline: SessionReplay.Timeline, frame: SessionReplay.Frame, accent: Color,
                lineWidth: CGFloat = 2, ground: Color = Color.onyx.slab) {
        self.timeline = timeline
        self.frame = frame
        self.accent = accent
        self.lineWidth = lineWidth
        self.ground = ground
    }

    private var dotRadius: CGFloat { lineWidth * 1.75 }

    public var body: some View {
        Canvas { ctx, size in
            // Room above the track for a dot to fall from and a record's ring
            // to bloom into; room at the sides so the first and last dots are
            // whole circles.
            let r = dotRadius
            let plot = CGRect(x: r * 2, y: r * 5, width: size.width - r * 4, height: size.height - r * 7)
            guard plot.width > 0, plot.height > 0 else { return }

            switch timeline.mode {
            case .trace: drawTrace(in: &ctx, plot: plot)
            case .tonnage: drawBars(in: &ctx, plot: plot)
            }
            drawDots(in: &ctx, plot: plot)
        }
        .accessibilityHidden(true)
    }

    // MARK: - The track

    private func point(_ p: SessionReplay.Point, in plot: CGRect) -> CGPoint {
        CGPoint(x: plot.minX + p.x * plot.width, y: plot.maxY - p.y * plot.height)
    }

    /// The trace up to `trackProgress`, its head interpolated so the pen moves
    /// smoothly between two resampled points instead of jumping.
    private func drawTrace(in ctx: inout GraphicsContext, plot: CGRect) {
        let progress = frame.trackProgress
        var drawn = timeline.trace.filter { $0.x <= progress }
        if let next = timeline.trace.first(where: { $0.x > progress }), let last = drawn.last {
            let f = (progress - last.x) / (next.x - last.x)
            drawn.append(.init(x: progress, y: last.y + (next.y - last.y) * f))
        }
        guard drawn.count >= 2 else { return }
        let points = drawn.map { point($0, in: plot) }

        // Smoothed through the midpoints (a quadratic per point): the
        // resampled series is 60 straight segments and read as raw noise.
        var line = Path()
        line.move(to: points[0])
        for i in 1..<points.count {
            let mid = CGPoint(x: (points[i - 1].x + points[i].x) / 2, y: (points[i - 1].y + points[i].y) / 2)
            line.addQuadCurve(to: mid, control: points[i - 1])
        }
        line.addLine(to: points[points.count - 1])
        // The area under the line — a wash, not a second line.
        var area = line
        area.addLine(to: CGPoint(x: points.last!.x, y: plot.maxY))
        area.addLine(to: CGPoint(x: points.first!.x, y: plot.maxY))
        area.closeSubpath()
        ctx.fill(area, with: .linearGradient(
            Gradient(colors: [OnyxInk.Fixed.heart.opacity(0.28), OnyxInk.Fixed.heart.opacity(0)]),
            startPoint: CGPoint(x: plot.midX, y: plot.minY), endPoint: CGPoint(x: plot.midX, y: plot.maxY)
        ))
        ctx.stroke(line, with: .color(OnyxInk.Fixed.heart),
                   style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

        // The pen, while it is still writing.
        if progress < 1, let head = points.last {
            let glow = lineWidth * 4
            ctx.fill(Path(ellipseIn: CGRect(x: head.x - glow, y: head.y - glow, width: glow * 2, height: glow * 2)),
                     with: .color(OnyxInk.Fixed.heart.opacity(0.25)))
            let nib = lineWidth * 1.6
            ctx.fill(Path(ellipseIn: CGRect(x: head.x - nib, y: head.y - nib, width: nib * 2, height: nib * 2)),
                     with: .color(OnyxInk.Fixed.heart))
        }
    }

    /// No heart rate: one bar, each movement's share of the work growing in
    /// turn, in the movement's own colour.
    private func drawBars(in ctx: inout GraphicsContext, plot: CGRect) {
        let height = max(lineWidth * 4, plot.height * 0.26)
        let y = plot.midY - height / 2
        let track = Path(roundedRect: CGRect(x: plot.minX, y: y, width: plot.width, height: height),
                         cornerRadius: height / 2)
        ctx.fill(track, with: .color(.white.opacity(0.06)))
        // Clipped to the track so the ends round and the joins stay square.
        ctx.drawLayer { layer in
            layer.clip(to: track)
            for (bar, growth) in zip(timeline.bars, frame.bars) where growth > 0 {
                let x = plot.minX + bar.from * plot.width
                // A hairline of ground between two movements.
                let width = max(0, (bar.to - bar.from) * plot.width * growth - (bar.to < 1 ? 1 : 0))
                layer.fill(Path(CGRect(x: x, y: y, width: width, height: height)),
                           with: .color(timeline.ink(bar.movement).opacity(0.85)))
            }
        }
    }

    // MARK: - The sets

    private func drawDots(in ctx: inout GraphicsContext, plot: CGRect) {
        let r = dotRadius
        let fall = r * 4
        for (dot, drop) in zip(timeline.dots, frame.drops) where drop > 0 {
            // Ease-out: fast from above, settling onto the track.
            let eased = 1 - pow(1 - drop, 3)
            let landed = point(.init(x: dot.x, y: timeline.mode == .trace ? dot.y : 0.5), in: plot)
            let c = CGPoint(x: landed.x, y: landed.y - fall * (1 - eased))
            let lit = dot.isRecord && frame.recordsLit
            let ink = lit ? OnyxInk.Fixed.record : accent

            if dot.isRecord, frame.recordGlow > 0 {
                // The one flash: a ping — a ring widening as it fades.
                let g = frame.recordGlow
                let ring = r * (1.5 + 1.2 * g)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - ring, y: c.y - ring, width: ring * 2, height: ring * 2)),
                         with: .color(OnyxInk.Fixed.record.opacity(0.12 * g)))
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - ring, y: c.y - ring, width: ring * 2, height: ring * 2)),
                           with: .color(OnyxInk.Fixed.record.opacity(0.9 * g)), lineWidth: max(1, lineWidth * 0.6))
            } else if lit {
                // After the flash a record keeps a quiet halo.
                let halo = r * 1.9
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - halo, y: c.y - halo, width: halo * 2, height: halo * 2)),
                         with: .color(OnyxInk.Fixed.record.opacity(0.18)))
            }

            // A ring of the ground around each dot: cut out of the line.
            var dotCtx = ctx
            dotCtx.opacity = min(1, drop * 3)
            let edge = r + max(1, lineWidth * 0.75)
            dotCtx.fill(Path(ellipseIn: CGRect(x: c.x - edge, y: c.y - edge, width: edge * 2, height: edge * 2)),
                        with: .color(ground))
            dotCtx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                        with: .color(ink))
        }
    }
}

/// The replay's one line of words: the movement the last dot belonged to, in
/// its own colour, while the replay runs; the session's count once it settles.
public struct ReplayCaption: View {
    /// What the line says — a finite set, so the video can draw each one ONCE
    /// and pick per frame (Precision B5) instead of laying type out 300 times.
    public enum State: Hashable, Sendable {
        case summary
        case movement(Int)
        case idle
    }

    let timeline: SessionReplay.Timeline
    let state: State
    let role: OnyxType
    /// Hold two lines' height whatever the line says — the share frame, whose
    /// video draws a two-line movement name into the slot the settled
    /// one-line summary was laid out for (Precision B5).
    let reservesTwoLines: Bool

    public init(timeline: SessionReplay.Timeline, frame: SessionReplay.Frame, role: OnyxType = .caption,
                reservesTwoLines: Bool = false) {
        self.init(timeline: timeline, state: Self.state(timeline, frame), role: role, reservesTwoLines: reservesTwoLines)
    }

    public init(timeline: SessionReplay.Timeline, state: State, role: OnyxType = .caption,
                reservesTwoLines: Bool = false) {
        self.timeline = timeline
        self.state = state
        self.role = role
        self.reservesTwoLines = reservesTwoLines
    }

    /// The one rule for which line a frame shows.
    public nonisolated static func state(_ timeline: SessionReplay.Timeline, _ frame: SessionReplay.Frame) -> State {
        if frame.settle > 0 || (frame.currentMovement == nil && frame.trackProgress >= 1) { return .summary }
        if let m = frame.currentMovement, timeline.movements.indices.contains(m) { return .movement(m) }
        return .idle
    }

    /// Every line the timeline can show, for the video's one-time pass.
    public nonisolated static func states(_ timeline: SessionReplay.Timeline) -> [State] {
        [.summary, .idle] + timeline.movements.indices.map(State.movement)
    }

    public var body: some View {
        Group {
            switch state {
            case .summary:
                summary
            case .movement(let m) where timeline.movements.indices.contains(m):
                Text(timeline.movements[m].name)
                    .foregroundStyle(timeline.ink(m))
            case .movement, .idle:
                Text("Replay")
                    .foregroundStyle(Color.onyx.textSecondary)
            }
        }
        .onyxType(role)
        .fontWeight(.semibold)
        // Two lines, not one: at AX5 "5 movements · 9…" truncated the count.
        .lineLimit(2, reservesSpace: reservesTwoLines)
        .minimumScaleFactor(0.8)
    }

    /// "3 movements · 18 sets". No PR count: the masthead beside every
    /// replay owns it, and two counts one line apart is how they came to
    /// disagree in the first shot.
    private var summary: Text {
        let moves = timeline.movements.count, sets = timeline.dots.count
        return Text("\(moves) \(moves == 1 ? "movement" : "movements") · \(sets) \(sets == 1 ? "set" : "sets")")
            .foregroundStyle(Color.onyx.textSecondary)
    }

    /// What VoiceOver reads for the whole replay.
    public static func accessibilityValue(_ timeline: SessionReplay.Timeline) -> String {
        let moves = timeline.movements.count, sets = timeline.dots.count
        var parts = ["\(sets) \(sets == 1 ? "set" : "sets") over \(moves) \(moves == 1 ? "movement" : "movements")"]
        if timeline.recordCount > 0 { parts.append("\(timeline.recordCount) \(timeline.recordCount == 1 ? "record" : "records")") }
        if timeline.mode == .trace { parts.append("with heart rate") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - The same drawing, in CoreGraphics (Precision B5, decision Q21)

/// `ReplayCanvas`'s drawing, ported to a `CGContext` so the ten-second MP4 is
/// drawn off the main actor: 300 `ImageRenderer` passes on the main thread
/// were the freeze the founder reported. Same shapes, same insets, same inks —
/// `ReplayCGRendererTests` holds the two drawings to within 2 % of each other's
/// pixels at 0, 5 and 10 s.
///
/// The inks are RESOLVED at init (on the main actor, where a `Color` resolves)
/// into sendable values, so the renderer can cross to the video actor.
public struct ReplayCGRenderer: Sendable {
    let timeline: SessionReplay.Timeline
    let lineWidth: CGFloat
    let accent: Color.Resolved
    let heart: Color.Resolved
    let record: Color.Resolved
    /// Nil = no ring cut round the dots (a clear ground).
    let ground: Color.Resolved?
    /// Per movement, `timeline.ink(_:)` resolved.
    let movementInks: [Color.Resolved]

    @MainActor
    public init(timeline: SessionReplay.Timeline, accent: Color, lineWidth: CGFloat = 2, ground: Color? = Color.onyx.slab) {
        let env = EnvironmentValues()
        self.timeline = timeline
        self.lineWidth = lineWidth
        self.accent = accent.resolve(in: env)
        self.heart = OnyxInk.Fixed.heart.resolve(in: env)
        self.record = OnyxInk.Fixed.record.resolve(in: env)
        self.ground = ground.map { $0.resolve(in: env) }
        self.movementInks = timeline.movements.indices.map { timeline.ink($0).resolve(in: env) }
    }

    private var dotRadius: CGFloat { lineWidth * 1.75 }

    private static func cg(_ c: Color.Resolved, _ alpha: Double = 1) -> CGColor {
        c.cgColor.copy(alpha: c.cgColor.alpha * alpha) ?? c.cgColor
    }

    /// Draws `frame` into `ctx` over `size` POINTS, with the context's origin
    /// at the TOP-left and y running down (the caller flips a bitmap context).
    public func draw(_ frame: SessionReplay.Frame, in ctx: CGContext, size: CGSize) {
        let r = dotRadius
        let plot = CGRect(x: r * 2, y: r * 5, width: size.width - r * 4, height: size.height - r * 7)
        guard plot.width > 0, plot.height > 0 else { return }
        switch timeline.mode {
        case .trace: drawTrace(frame, ctx, plot)
        case .tonnage: drawBars(frame, ctx, plot)
        }
        drawDots(frame, ctx, plot)
    }

    /// A whole frame as an image — the test's view of the port, and any
    /// caller that wants one frame without a context of its own.
    public func image(_ frame: SessionReplay.Frame, size: CGSize, scale: CGFloat, background: Color? = nil) -> CGImage? {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if let background {
            ctx.setFillColor(Self.cg(background.resolve(in: EnvironmentValues())))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        draw(frame, in: ctx, size: size)
        return ctx.makeImage()
    }

    private func point(_ p: SessionReplay.Point, in plot: CGRect) -> CGPoint {
        CGPoint(x: plot.minX + p.x * plot.width, y: plot.maxY - p.y * plot.height)
    }

    private func drawTrace(_ frame: SessionReplay.Frame, _ ctx: CGContext, _ plot: CGRect) {
        let progress = frame.trackProgress
        var drawn = timeline.trace.filter { $0.x <= progress }
        if let next = timeline.trace.first(where: { $0.x > progress }), let last = drawn.last {
            let f = (progress - last.x) / (next.x - last.x)
            drawn.append(.init(x: progress, y: last.y + (next.y - last.y) * f))
        }
        guard drawn.count >= 2 else { return }
        let points = drawn.map { point($0, in: plot) }

        let line = CGMutablePath()
        line.move(to: points[0])
        for i in 1..<points.count {
            let mid = CGPoint(x: (points[i - 1].x + points[i].x) / 2, y: (points[i - 1].y + points[i].y) / 2)
            line.addQuadCurve(to: mid, control: points[i - 1])
        }
        line.addLine(to: points[points.count - 1])

        let area = line.mutableCopy()!
        area.addLine(to: CGPoint(x: points.last!.x, y: plot.maxY))
        area.addLine(to: CGPoint(x: points.first!.x, y: plot.maxY))
        area.closeSubpath()
        ctx.saveGState()
        ctx.addPath(area)
        ctx.clip()
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                     colors: [Self.cg(heart, 0.28), Self.cg(heart, 0)] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: plot.midX, y: plot.minY),
                                   end: CGPoint(x: plot.midX, y: plot.maxY), options: [])
        }
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(line)
        ctx.setStrokeColor(Self.cg(heart))
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()

        if progress < 1, let head = points.last {
            let glow = lineWidth * 4
            ctx.setFillColor(Self.cg(heart, 0.25))
            ctx.fillEllipse(in: CGRect(x: head.x - glow, y: head.y - glow, width: glow * 2, height: glow * 2))
            let nib = lineWidth * 1.6
            ctx.setFillColor(Self.cg(heart))
            ctx.fillEllipse(in: CGRect(x: head.x - nib, y: head.y - nib, width: nib * 2, height: nib * 2))
        }
    }

    private func drawBars(_ frame: SessionReplay.Frame, _ ctx: CGContext, _ plot: CGRect) {
        let height = max(lineWidth * 4, plot.height * 0.26)
        let y = plot.midY - height / 2
        let track = CGPath(roundedRect: CGRect(x: plot.minX, y: y, width: plot.width, height: height),
                           cornerWidth: height / 2, cornerHeight: height / 2, transform: nil)
        ctx.saveGState()
        ctx.addPath(track)
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.06))
        ctx.fillPath()
        ctx.addPath(track)
        ctx.clip()
        for (bar, growth) in zip(timeline.bars, frame.bars) where growth > 0 {
            let x = plot.minX + bar.from * plot.width
            let width = max(0, (bar.to - bar.from) * plot.width * growth - (bar.to < 1 ? 1 : 0))
            let ink = movementInks.indices.contains(bar.movement) ? movementInks[bar.movement] : heart
            ctx.setFillColor(Self.cg(ink, 0.85))
            ctx.fill(CGRect(x: x, y: y, width: width, height: height))
        }
        ctx.restoreGState()
    }

    private func drawDots(_ frame: SessionReplay.Frame, _ ctx: CGContext, _ plot: CGRect) {
        let r = dotRadius
        let fall = r * 4
        for (dot, drop) in zip(timeline.dots, frame.drops) where drop > 0 {
            let eased = 1 - pow(1 - drop, 3)
            let landed = point(.init(x: dot.x, y: timeline.mode == .trace ? dot.y : 0.5), in: plot)
            let c = CGPoint(x: landed.x, y: landed.y - fall * (1 - eased))
            let lit = dot.isRecord && frame.recordsLit
            let ink = lit ? record : accent

            if dot.isRecord, frame.recordGlow > 0 {
                let g = frame.recordGlow
                let ring = r * (1.5 + 1.2 * g)
                let rect = CGRect(x: c.x - ring, y: c.y - ring, width: ring * 2, height: ring * 2)
                ctx.setFillColor(Self.cg(record, 0.12 * g))
                ctx.fillEllipse(in: rect)
                // `strokeBorder`-free: SwiftUI's `stroke` straddles the path.
                ctx.setStrokeColor(Self.cg(record, 0.9 * g))
                ctx.setLineWidth(max(1, lineWidth * 0.6))
                ctx.strokeEllipse(in: rect)
            } else if lit {
                let halo = r * 1.9
                ctx.setFillColor(Self.cg(record, 0.18))
                ctx.fillEllipse(in: CGRect(x: c.x - halo, y: c.y - halo, width: halo * 2, height: halo * 2))
            }

            ctx.saveGState()
            ctx.setAlpha(min(1, drop * 3))
            if let ground {
                let edge = r + max(1, lineWidth * 0.75)
                ctx.setFillColor(Self.cg(ground))
                ctx.fillEllipse(in: CGRect(x: c.x - edge, y: c.y - edge, width: edge * 2, height: edge * 2))
            }
            ctx.setFillColor(Self.cg(ink))
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.restoreGState()
        }
    }
}
