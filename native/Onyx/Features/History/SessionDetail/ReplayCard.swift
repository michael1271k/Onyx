import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

// ─────────────────────────────────────────────────────────────────────────────
// Session Replay on the phone (overhaul W5, feature 2) — since Precision B1
// (decision Q16) the BACKDROP of the summary's masthead, not a row of its own.
//
// Ten seconds, once, on arrival: the heart-rate trace draws itself behind the
// name and the figures, every set drops onto it where it was logged, the
// records flash gold. A tap on the slab plays it again. Reduce Motion never
// plays it — the slab opens on the final frame, which is also exactly what
// the share PNGs draw.
//
// Nothing here is stored. The replay is rebuilt from what the page already
// read (the report, the telemetry cache) plus one indexed read of the set log
// for the commit clocks.
// ─────────────────────────────────────────────────────────────────────────────

extension SessionReplay.Input {

    /// Each set's commit time, keyed `exerciseId|setIndex` — the FIRST append
    /// the log holds for it (an amend never moves when a set was done).
    static func clocks(database: AppDatabase, sessionId: String) -> [String: Date] {
        var out: [String: Date] = [:]
        for event in (try? database.setEvents(sessionId: sessionId)) ?? [] {
            guard case .append(let set) = event.body else { continue }
            let key = "\(set.exerciseId)|\(set.setIndex)"
            if out[key].map({ event.createdAt < $0 }) ?? true { out[key] = event.createdAt }
        }
        return out
    }

    /// The replay of one summary page. `samples` is the page's own heart-rate
    /// read (empty → the tonnage bar); `clocks` from `clocks(database:…)`.
    static func session(_ page: SessionAnalysis.Page, label: String, samples: [HRSample],
                        clocks: [String: Date]) -> SessionReplay.Input {
        let report = page.report, session = report.session
        var masthead = SessionMasthead(page: page, label: label)
        masthead.hrSpark = SessionMasthead.spark(samples.map { Double($0.bpm) })
        let start = session.startedAt ?? masthead.startedAt
        let end = session.endedAt ?? start.addingTimeInterval(Double(max(masthead.durationSec, 60)))
        var sets: [SessionReplay.SetMark] = []
        for (m, exercise) in report.exercises.enumerated() {
            // `records` is keyed by set NUMBER, which the two sides of a pair
            // share, and holds each side's won axes — while the engine counts
            // an axis once per set. So a number's DISTINCT axes go on its first
            // row only, or a unilateral record is flashed twice (11 flashes
            // under a masthead that said 9, in the first shot).
            var credited = Set<Int>()
            for set in exercise.detail.sets {
                let number = Int(set.setNumber)
                let axes = Set((exercise.records[number] ?? []).map(\.axis))
                sets.append(SessionReplay.SetMark(
                    movement: m,
                    at: clocks["\(exercise.detail.exerciseId)|\(number)"],
                    records: credited.insert(number).inserted ? axes.count : 0
                ))
            }
        }
        return SessionReplay.Input(
            masthead: masthead, start: start, end: end, samples: samples,
            movements: report.exercises.map { .init(name: $0.canonical, tonnageKg: $0.detail.volumeKg) },
            sets: sets
        )
    }
}

/// Row 1 of `SessionDetailView`: the masthead slab with the replay drawn
/// inside it (Precision B1, design 4 "Masthead-with-replay").
///
/// ── WHY THE REPLAY LOST ITS ROW ─────────────────────────────────────────────
/// The card was ~150 pt of slab that said the same session a second time,
/// above the masthead that said it first: a caption, a trace and a share
/// glyph, then the name and the figures. The trace is the picture OF the
/// figures, so it now sits behind them at 35 % — one slab, zero extra rows —
/// and the share glyph moved with it to the slab's trailing corner.
///
/// `OnyxMasthead` is unchanged on top. The second line under it is the focus
/// pills (top three), which used to be a row of their own under the grid.
struct ReplayMasthead: View {
    let masthead: SessionMasthead
    let dayKey: String?
    /// The backdrop: the replay as the tonnage rail. Nil for a session with
    /// no movements — nothing to replay, and the slab is just the masthead.
    let timeline: SessionReplay.Timeline?
    /// What the share files draw: the same replay WITH the heart-rate trace
    /// when the session has one.
    let shareTimeline: SessionReplay.Timeline?
    let muscles: [(muscle: LandmarkMuscle, sets: Double)]
    let sessionId: String
    /// The session's logical day, for the share frames' date line.
    let day: Date
    /// False until the page's heart-rate read has answered: a replay that
    /// started on the tonnage bar and swapped to the trace a beat later would
    /// be two replays.
    let ready: Bool
    let onFocus: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When the running replay began; nil at rest on the final frame.
    @State private var startedAt: Date?
    @State private var played = false
    /// The PNGs, pre-baked once the heart-rate read lands (Precision B5).
    /// The share button appears when they exist: a sheet opened before them
    /// had nothing to show but an SF Symbol.
    @State private var shareSet: ReplayShareSet?

    private var accent: Color { OnyxInk.Themed.accent }
    private var dayInk: Color { Color.onyx.day(dayKey) }

    var body: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            OnyxMasthead(masthead, accent: dayInk)
                // The share glyph's room on the trailing edge.
                .padding(.trailing, shareTimeline == nil ? 0 : 36)
            if !muscles.isEmpty {
                FocusPills(muscles: muscles, limit: 3, onOpen: onFocus)
            }
        }
        .padding(OnyxSpace.m)
        // The tonnage rail's lane under the pills (see `backdrop`).
        .padding(.bottom, railTimeline == nil ? 0 : Self.railLane)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) { backdrop }
        .sessionDayWash(dayKey)
        .onyxGlass(.tile)
        .contentShape(RoundedRectangle(cornerRadius: OnyxCorner.tile, style: .continuous))
        .onTapGesture(perform: play)
        .overlay(alignment: .topTrailing) { share }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Replay", play)
        .onChange(of: ready, initial: true) { _, isReady in
            // Once, on arrival — never again on a rescore or a scroll back.
            guard isReady, !played else { return }
            played = true
            play()
        }
        // The share files, once, as soon as the replay they draw is final —
        // after the heart-rate read, so the PNGs carry the trace.
        .task(id: ready) {
            guard ready, shareSet == nil, let shareTimeline else { return }
            // Let the arrival frame draw first: the two passes are ~100 ms.
            await Task.yield()
            let source = ReplaySource(timeline: shareTimeline, dayInk: dayInk, sessionId: sessionId, day: day)
            shareSet = try? ReplayShareSet.prebake(source)
        }
        // Back to rest once the ten seconds are up, so the TimelineView stops
        // asking for frames.
        .task(id: startedAt) {
            guard startedAt != nil, let timeline = railTimeline else { return }
            try? await Task.sleep(for: .seconds(timeline.duration))
            if !Task.isCancelled { startedAt = nil }
        }
    }

    /// The tonnage rail's canvas: room for a dot to fall onto an 8 pt bar.
    static let railHeight: CGFloat = 32
    /// What the slab adds under the pills for the rail to run in.
    static let railLane: CGFloat = 16

    /// The replay, at 35 %, pinned to the slab's foot. Clipped by the slab's
    /// own `onyxGlass` (it is a background INSIDE it), so nothing paints past
    /// the corner.
    ///
    /// ── A RAIL BENEATH, NEVER A TRACE BEHIND (shot rounds 1–2) ─────────────
    /// The brief asked for the replay behind the masthead. Drawn as the
    /// heart-rate trace at the slab's height it ran through the figures and
    /// the pills (and through every line of type at AX5), and it said the
    /// heart rate a second time directly above the heart-rate strip. As the
    /// tonnage BAR at the slab's height it was a 36 pt stripe through the
    /// pills. So the backdrop is the replay's tonnage rail, thin, in its own
    /// lane under the pills — the sets still drop and the records still flash
    /// — and the trace lives in the strip and in the share files. The dots
    /// take no ring of ground here (`.clear`): a ring cut in slab ink is a
    /// dark hole behind text.
    @ViewBuilder
    private var backdrop: some View {
        if let timeline = railTimeline {
            TimelineView(.animation(paused: startedAt == nil)) { context in
                ReplayCanvas(timeline: timeline, frame: frame(timeline, at: context.date),
                             accent: accent, ground: .clear)
                    .frame(height: Self.railHeight)
                    .opacity(0.35)
            }
            .accessibilityHidden(true)
        }
    }

    /// The rail, when it has something to show: a cardio-only session is a
    /// bar of zero tonnage — one flat stripe that says nothing (critique).
    private var railTimeline: SessionReplay.Timeline? {
        guard let timeline, timeline.movements.contains(where: { $0.tonnageKg > 0 }) else { return nil }
        return timeline
    }

    @ViewBuilder
    private var share: some View {
        if let shareSet {
            ShareLink(
                items: shareSet.items,
                subject: Text(shareSet.items[0].source.timeline.masthead.name),
                message: Text(shareSet.message)
            ) { item in
                // The square itself, small — the preview used to be an SF
                // Symbol because nothing had been rendered yet.
                SharePreview(item.title, image: Image(uiImage: shareSet.thumbnail))
            } label: {
                shareGlyph
            }
            .accessibilityLabel("Share replay")
            .accessibilityHint("A square image, a Stories image and a ten-second video.")
        } else if shareTimeline != nil {
            // Held in place while the two PNGs bake, so nothing moves when
            // the button goes live.
            shareGlyph
                .opacity(0.35)
                .accessibilityHidden(true)
        }
    }

    private var shareGlyph: some View {
        Image(systemName: "square.and.arrow.up")
            .onyxType(.body)
            // Capped: at AX5 the glyph outgrew its 44 pt target and hung over
            // the card's edge.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .foregroundStyle(accent)
            .frame(width: 44, height: 44)
            .contentShape(.rect)
    }

    private func frame(_ timeline: SessionReplay.Timeline, at date: Date) -> SessionReplay.Frame {
        guard let startedAt, ready else { return ready ? timeline.final : timeline.frame(at: 0) }
        return timeline.frame(at: date.timeIntervalSince(startedAt))
    }

    private func play() {
        guard !reduceMotion, ready, railTimeline != nil else { return }
        startedAt = Date()
    }
}
