import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

// ─────────────────────────────────────────────────────────────────────────────
// Session Replay on the phone (overhaul W5, feature 2): row 0 of the summary.
//
// Ten seconds, once, on arrival: the heart-rate trace draws itself, every set
// drops onto it where it was logged, the records flash gold, the count settles.
// A tap plays it again. Reduce Motion never plays it — the card opens on the
// final frame, which is also exactly what the share PNGs draw.
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
            // share — so a number's records go on its first row only, or a
            // unilateral record is flashed twice (11 flashes under a masthead
            // that said 9, in the first shot).
            var credited = Set<Int>()
            for set in exercise.detail.sets {
                let number = Int(set.setNumber)
                sets.append(SessionReplay.SetMark(
                    movement: m,
                    at: clocks["\(exercise.detail.exerciseId)|\(number)"],
                    records: credited.insert(number).inserted ? (exercise.records[number]?.count ?? 0) : 0
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

/// Row 0 of `SessionDetailView`.
struct ReplayCard: View {
    let timeline: SessionReplay.Timeline
    /// The split's own colour — the share frames' masthead bar.
    let dayInk: Color
    let sessionId: String
    /// The session's logical day, for the share frames' date line.
    let day: Date
    /// False until the page's heart-rate read has answered: a replay that
    /// started on the tonnage bar and swapped to the trace a beat later would
    /// be two replays.
    let ready: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When the running replay began; nil at rest on the final frame.
    @State private var startedAt: Date?
    @State private var played = false

    private var accent: Color { OnyxInk.Themed.accent }

    var body: some View {
        TimelineView(.animation(paused: startedAt == nil)) { context in
            let frame = frame(at: context.date)
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                ReplayCaption(timeline: timeline, frame: frame)
                    // The share button's room on the trailing edge.
                    .padding(.trailing, 44)
                    .frame(minHeight: 28, alignment: .leading)
                ReplayCanvas(timeline: timeline, frame: frame, accent: accent)
                    // A bar needs a line, not a chart's height: 88 pt around
                    // an 18 pt bar was mostly empty slab in the first shot.
                    .frame(height: timeline.mode == .trace ? 88 : 48)
            }
        }
        .padding(OnyxSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onyxGlass(.tile)
        .contentShape(RoundedRectangle(cornerRadius: OnyxCorner.tile, style: .continuous))
        .onTapGesture(perform: play)
        .overlay(alignment: .topTrailing) {
            ShareLink(items: ReplayShareItem.all(timeline: timeline, dayInk: dayInk, sessionId: sessionId, day: day)) { item in
                SharePreview(item.title, icon: Image(systemName: item.symbol))
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .onyxType(.body)
                    // Capped: at AX5 the glyph outgrew its 44 pt target and
                    // hung over the card's edge.
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .padding(OnyxSpace.xs)
            .accessibilityLabel("Share replay")
            .accessibilityHint("A square image, a Stories image and a ten-second video.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session replay")
        .accessibilityValue(ReplayCaption.accessibilityValue(timeline))
        .accessibilityAction(named: "Replay", play)
        .onChange(of: ready, initial: true) { _, isReady in
            // Once, on arrival — never again on a rescore or a scroll back.
            guard isReady, !played else { return }
            played = true
            play()
        }
        // Back to rest once the ten seconds are up, so the TimelineView stops
        // asking for frames.
        .task(id: startedAt) {
            guard startedAt != nil else { return }
            try? await Task.sleep(for: .seconds(timeline.duration))
            if !Task.isCancelled { startedAt = nil }
        }
    }

    private func frame(at date: Date) -> SessionReplay.Frame {
        guard let startedAt, ready else { return ready ? timeline.final : timeline.frame(at: 0) }
        return timeline.frame(at: date.timeIntervalSince(startedAt))
    }

    private func play() {
        guard !reduceMotion, ready else { return }
        startedAt = Date()
    }
}
