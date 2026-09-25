import SwiftUI
import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers
import OnyxUI
import OnyxCore
import os

// ─────────────────────────────────────────────────────────────────────────────
// The replay, shared (overhaul W5; pre-baked since Precision B5, decision Q21):
// a 1080×1080 PNG, a 1080×1920 Stories PNG, and a ten-second 1080×1920 MP4.
//
// ── WHY THE SHEET USED TO FREEZE, AND WHAT CHANGED ──────────────────────────
// Every item was rendered inside its exporting closure, on the main actor: the
// PNGs when the sheet asked for a preview, the MP4 as 300 `ImageRenderer`
// passes with a `Task.yield()` between them. The sheet waited on the main
// thread it needed to draw itself, and its preview was an SF Symbol because
// nothing had been rendered yet — "Replay share freezes and shares an empty
// image". Now:
//
//   · the two PNGs are rendered ONCE when the summary's heart-rate read lands
//     (`ReplayShareSet.prebake`, two passes on the main actor) into the temp
//     folder, and the share button appears only once they exist — the sheet
//     opens on files, with the square as its real thumbnail;
//   · the MP4 is drawn by `ReplayVideoRenderer`, an actor: ONE plate (the card
//     without its canvas) and one image per caption line are rendered on the
//     main actor, one at a time; every frame after that is CoreGraphics
//     (`ReplayCGRenderer`, OnyxUI) into the writer's pixel buffers, off it.
//
// ── WHY 360 × 640 POINTS AT SCALE 3, NOT 1080 × 1920 AT SCALE 1 ──────────────
// The pixels are the same 1080 × 1920. The frame reuses the app's own faces —
// `OnyxMasthead`, `ReplayCaption` — whose type is Dynamic Type roles in points;
// laid out 1080 points wide, the masthead's 15 pt figures would be 1.4 % of the
// frame's width. A phone-sized layout rendered at 3× is the frame a person
// would see on their own screen, at Stories resolution.
//
// ── AND WHY THE FROST IS PAINTED ────────────────────────────────────────────
// `ImageRenderer` has no render server, so `.thinMaterial` draws NOTHING in it
// (`WeeklyWrapContent.render` says the same). The Stone slab's frost is
// therefore painted: the slab at the app's own 0.78 over the backdrop, a 4 %
// white lift, a sheen on the top edge and one lit border — the look
// `.onyxGlass` has over this backdrop, without the blur (nothing to sample).
// ─────────────────────────────────────────────────────────────────────────────

/// What every share format is drawn from — the replay and the few facts the
/// frame prints, all sendable.
struct ReplaySource: Sendable {
    let timeline: SessionReplay.Timeline
    /// Read on the main actor from the theme the page is drawn in — the
    /// renderers must not re-read a global later.
    let accent: Color
    let dayInk: Color
    let sessionId: String
    /// The session's logical day — what the page's title says.
    let day: Date

    @MainActor
    init(timeline: SessionReplay.Timeline, dayInk: Color, sessionId: String, day: Date) {
        self.timeline = timeline
        self.accent = OnyxInk.Themed.accent
        self.dayInk = dayInk
        self.sessionId = sessionId
        self.day = day
    }

    /// "Onyx · Upper B · 4.4 t · onyx://session/<uuid>" — the text the share
    /// sheet sends with the files; the link opens this summary (`SessionLink`).
    var message: String {
        var parts = ["Onyx", timeline.masthead.name]
        if let tonnes = OnyxSnapshot.tonnes(timeline.masthead.tonnageKg > 0 ? timeline.masthead.tonnageKg : nil) {
            parts.append(tonnes)
        }
        parts.append(SessionLink.url(sessionId: sessionId).absoluteString)
        return parts.joined(separator: " · ")
    }

    /// "onyx-upper-b-2026-09-18" — the file name the recipient sees.
    var slug: String {
        let name = timeline.masthead.name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return "onyx-\(String(name).split(separator: "-").joined(separator: "-"))-\(LogicalDay.iso(day))"
    }
}

/// One thing the share sheet offers.
struct ReplayShareItem: Transferable, Sendable {
    enum Kind: String, Sendable, CaseIterable { case square, stories, video }

    let kind: Kind
    let source: ReplaySource
    /// The PNG `prebake` already wrote; nil for the video.
    let file: URL?

    var title: String {
        switch kind {
        case .square: "\(source.timeline.masthead.name) — square"
        case .stories: "\(source.timeline.masthead.name) — Stories"
        case .video: "\(source.timeline.masthead.name) — replay video"
        }
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { item in
            // Pre-baked: the sheet is handed a file that already exists.
            if let file = item.file { return SentTransferredFile(file) }
            return SentTransferredFile(try await MainActor.run { try ReplayExporter.png(item.source, kind: item.kind) })
        }
        .exportingCondition { $0.kind != .video }
        FileRepresentation(exportedContentType: .mpeg4Movie) { item in
            // Awaits the actor; the main thread is free while it draws.
            SentTransferredFile(try await ReplayVideoRenderer.shared.video(item.source))
        }
        .exportingCondition { $0.kind == .video }
    }
}

/// The three items and the thumbnail, made once per summary (Precision B5).
struct ReplayShareSet {
    let items: [ReplayShareItem]
    /// The square PNG, small — the share sheet's real preview. Nil only when
    /// the pre-bake failed and the set fell back to rendering on request.
    let thumbnail: UIImage?
    let message: String

    private static let log = Logger(subsystem: "app.onyx.health", category: "replay")

    /// Two `ImageRenderer` passes (square, Stories) on the main actor — the
    /// only part that needs it — then the PNG encode, the two writes and the
    /// thumbnail off it (review: the encode and the disk were on the main
    /// thread during the summary's arrival).
    ///
    /// A failure is logged and falls back to the lazy set (files rendered
    /// when the sheet asks, as before 10.0), never to a dead button.
    @MainActor
    static func prebake(_ source: ReplaySource) async -> ReplayShareSet {
        let began = Date()
        do {
            let squareImage = try ReplayExporter.finalFrame(source, kind: .square)
            let storiesImage = try ReplayExporter.finalFrame(source, kind: .stories)
            let rendered = Date()
            let baked = try await Task.detached(priority: .userInitiated) {
                let square = try ReplayExporter.write(squareImage, source: source, kind: .square)
                let stories = try ReplayExporter.write(storiesImage, source: source, kind: .stories)
                let thumb = UIImage(cgImage: squareImage).preparingThumbnail(of: CGSize(width: 240, height: 240))
                return (square, stories, thumb)
            }.value
            log.notice("replay prebake: \(Int(rendered.timeIntervalSince(began) * 1000)) ms on the main actor, \(Int(Date().timeIntervalSince(began) * 1000)) ms in all")
            return ReplayShareSet(items: items(source, square: baked.0, stories: baked.1),
                                  thumbnail: baked.2, message: source.message)
        } catch {
            log.error("replay prebake failed: \(String(describing: error), privacy: .public)")
            return ReplayShareSet(items: items(source, square: nil, stories: nil), thumbnail: nil, message: source.message)
        }
    }

    private static func items(_ source: ReplaySource, square: URL?, stories: URL?) -> [ReplayShareItem] {
        [
            ReplayShareItem(kind: .square, source: source, file: square),
            ReplayShareItem(kind: .stories, source: source, file: stories),
            ReplayShareItem(kind: .video, source: source, file: nil),
        ]
    }
}

/// The frame every share format draws — the replay card on a backdrop made
/// for a Stories screen.
struct ReplayShareFrame: View {
    enum Format {
        case square, stories

        /// Points; rendered at `ReplayExporter.scale`.
        var size: CGSize {
            switch self {
            case .square: CGSize(width: 360, height: 360)
            case .stories: CGSize(width: 360, height: 640)
            }
        }

        /// Instagram's reserved bands (250 / 340 px at 1080 × 1920), in points.
        var safeTop: CGFloat { self == .stories ? 250 / ReplayExporter.scale : 0 }
        var safeBottom: CGFloat { self == .stories ? 340 / ReplayExporter.scale : 0 }
    }

    let format: Format
    let timeline: SessionReplay.Timeline
    let frame: SessionReplay.Frame
    let accent: Color
    let dayInk: Color
    let day: Date
    /// The video's plate (Precision B5): the card with its canvas and caption
    /// laid out but not drawn, and the masthead settled — the parts that move
    /// are drawn per frame by CoreGraphics into the slots `probe` reports.
    var plate = false
    var probe: ShareProbe? = nil

    /// Where the canvas and the caption landed, in points — written during
    /// layout by the plate pass, read by the video actor.
    final class ShareProbe: @unchecked Sendable {
        var canvas: CGRect = .zero
        var caption: CGRect = .zero
    }

    /// The card's own surface, flattened — the ring each dot is cut out with.
    static let cardInk = Color.onyx.slab.mix(with: .white, by: 0.08)
    static let lineWidth: CGFloat = 2.5

    var body: some View {
        let size = format.size
        // Card and wordmark are ONE block, centred in the safe band — the
        // wordmark floating at the bottom read as a second, unrelated object.
        VStack(spacing: format == .stories ? 28 : OnyxSpace.l) {
            card
                .frame(width: size.width * 0.72)
            wordmark
        }
        .frame(maxHeight: .infinity)
        .padding(.top, format.safeTop)
        .padding(.bottom, format.safeBottom)
        .frame(width: size.width, height: size.height)
        .background { backdrop }
        .coordinateSpace(.named(Self.space))
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .large)
    }

    private static let space = "replay.share"

    /// A slot's frame, reported to the probe as layout happens.
    private func report(_ keyPath: ReferenceWritableKeyPath<ShareProbe, CGRect>) -> some View {
        GeometryReader { proxy in
            let _ = Self.record(proxy.frame(in: .named(Self.space)), into: probe, at: keyPath)
            Color.clear
        }
    }

    private static func record(_ rect: CGRect, into probe: ShareProbe?,
                               at keyPath: ReferenceWritableKeyPath<ShareProbe, CGRect>) -> Bool {
        probe?[keyPath: keyPath] = rect
        return true
    }

    /// A deep two-stop radial of the theme accent over near-black, lit a
    /// little above the card's centre so the light falls ON the data; a
    /// fainter glow high on the left breaks the symmetry, and a vignette
    /// takes the corners to black so the frame has depth, not a haze.
    private var backdrop: some View {
        let h = format.size.height
        return ZStack {
            Color.onyx.slab
            RadialGradient(
                colors: [accent.opacity(0.5), Color.onyx.slab.opacity(0)],
                center: UnitPoint(x: 0.5, y: 0.4),
                startRadius: 0,
                endRadius: format == .stories ? 380 : 300
            )
            RadialGradient(
                colors: [accent.opacity(0.18), accent.opacity(0)],
                center: UnitPoint(x: 0.12, y: 0.06),
                startRadius: 0,
                endRadius: 240
            )
            RadialGradient(
                colors: [.black.opacity(0), .black.opacity(0.5)],
                center: .center,
                startRadius: h * 0.47,
                endRadius: h * 0.875
            )
        }
    }

    private var card: some View {
        return VStack(alignment: .leading, spacing: OnyxSpace.m) {
            Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())
                .onyxType(.micro, tracking: 0.08)
                .fontWeight(.semibold)
                .foregroundStyle(Color.onyx.textSecondary)
            // Present from frame 0 and COUNTING UP with the replay — it
            // settles on the real figures at the end (the share round: a
            // masthead hidden until 9 s left the card's top empty for most of
            // a video that Stories may never let run to its end).
            OnyxMasthead(timeline.masthead(at: plate ? timeline.final : frame), accent: dayInk)
            ReplayCanvas(timeline: timeline, frame: frame, accent: accent,
                         lineWidth: Self.lineWidth, ground: Self.cardInk)
                .frame(height: format == .stories ? 170 : 96)
                .opacity(plate ? 0 : 1)
                .background { report(\.canvas) }
            ReplayCaption(timeline: timeline, frame: frame, reservesTwoLines: true)
                .opacity(plate ? 0 : 1)
                .background { report(\.caption) }
        }
        .padding(20)
        .background { frost }
    }

    /// The Stone slab, painted (see the file header).
    private var frost: some View {
        // At the app's own slab tint (0.78): at 0.62 the backdrop's radial
        // showed through as a bullseye in the middle of the card.
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return shape
            .fill(Color.onyx.slab.opacity(Color.onyx.slabTint))
            .overlay { shape.fill(.white.opacity(0.04)) }
            .overlay {
                shape.fill(LinearGradient(
                    stops: [.init(color: .white.opacity(0.06), location: 0), .init(color: .white.opacity(0), location: 0.12)],
                    startPoint: .top, endPoint: .bottom
                ))
            }
            .overlay {
                shape.strokeBorder(LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.16), location: 0),
                        .init(color: .white.opacity(0.03), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                ), lineWidth: 1)
            }
    }

    private var wordmark: some View {
        HStack(spacing: OnyxSpace.s) {
            OnyxMark(size: 18, opacity: 1)
            OnyxWordmark(role: .secondary)
        }
        .opacity(0.7)
    }
}

/// The PNGs and the video's plate. Main actor because `ImageRenderer` is.
@MainActor
enum ReplayExporter {
    /// 360 × 640 points → 1080 × 1920 pixels.
    nonisolated static let scale: CGFloat = 3
    nonisolated static let fps: Int32 = 30

    enum Failure: Error { case render, writer(String) }

    /// `tmp/replay/<session id>/<readable name>` — one folder per session, so
    /// two sessions with one label on one day never overwrite each other's
    /// files (review), and the name the recipient sees stays readable.
    nonisolated static func url(_ source: ReplaySource, _ kind: ReplayShareItem.Kind, _ ext: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "replay", directoryHint: .isDirectory)
            .appending(path: source.sessionId.isEmpty ? "session" : source.sessionId, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "\(source.slug)-\(kind.rawValue).\(ext)")
    }

    static func renderer(_ source: ReplaySource, format: ReplayShareFrame.Format, frame: SessionReplay.Frame,
                         plate: Bool = false, probe: ReplayShareFrame.ShareProbe? = nil) -> ImageRenderer<ReplayShareFrame> {
        let renderer = ImageRenderer(content: ReplayShareFrame(
            format: format, timeline: source.timeline, frame: frame,
            accent: source.accent, dayInk: source.dayInk, day: source.day, plate: plate, probe: probe
        ))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(format.size)
        return renderer
    }

    /// The final frame as a PNG — `square` at 1080², `stories` at 1080 × 1920.
    static func png(_ source: ReplaySource, kind: ReplayShareItem.Kind) throws -> URL {
        try write(finalFrame(source, kind: kind), source: source, kind: kind)
    }

    /// The render — the one part that needs the main actor.
    static func finalFrame(_ source: ReplaySource, kind: ReplayShareItem.Kind) throws -> CGImage {
        let format: ReplayShareFrame.Format = kind == .square ? .square : .stories
        guard let image = renderer(source, format: format, frame: source.timeline.final).cgImage
        else { throw Failure.render }
        return image
    }

    /// Encode and write — anywhere.
    nonisolated static func write(_ image: CGImage, source: ReplaySource, kind: ReplayShareItem.Kind) throws -> URL {
        guard let data = UIImage(cgImage: image).pngData() else { throw Failure.render }
        let out = try url(source, kind, "png")
        try data.write(to: out, options: .atomic)
        return out
    }

    /// The Stories card without its moving parts, plus one image per caption
    /// line — everything the video needs from SwiftUI, made once.
    static func plate(_ source: ReplaySource) throws -> ReplayVideoRenderer.Plate {
        let probe = ReplayShareFrame.ShareProbe()
        guard let background = renderer(source, format: .stories, frame: source.timeline.final,
                                         plate: true, probe: probe).cgImage,
              // The slots come from a layout side effect: if it did not run,
              // every frame would draw nothing into a zero rect (review).
              probe.canvas.width > 0, probe.caption.width > 0
        else { throw Failure.render }
        return ReplayVideoRenderer.Plate(
            background: background,
            canvas: probe.canvas.applying(CGAffineTransform(scaleX: scale, y: scale)),
            caption: probe.caption.applying(CGAffineTransform(scaleX: scale, y: scale)),
            captions: [:],
            renderer: ReplayCGRenderer(timeline: source.timeline, accent: source.accent,
                                       lineWidth: ReplayShareFrame.lineWidth, ground: ReplayShareFrame.cardInk)
        )
    }

    /// One caption line at the slot's width, on a clear ground.
    static func caption(_ source: ReplaySource, _ state: ReplayCaption.State, width: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content:
            ReplayCaption(timeline: source.timeline, state: state, reservesTwoLines: true)
                .frame(width: width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.colorScheme, .dark)
                .environment(\.dynamicTypeSize, .large)
        )
        renderer.scale = scale
        return renderer.cgImage
    }
}

/// The MP4, drawn off the main actor (Precision B5, decision Q21).
///
/// ── ONE PLATE, THEN CORE GRAPHICS ───────────────────────────────────────────
/// The card, the masthead, the date and the wordmark do not move between
/// frames (the masthead is the settled one: the count-up the old video drew
/// was 300 layout passes of type), so they are ONE image. The caption has a
/// handful of possible lines, so it is a handful of images. What moves — the
/// trace, the bars, the dots — is `ReplayCGRenderer`, drawn straight into the
/// writer's pixel buffers. The main actor pays for `2 + movements` renders,
/// one hop each; the 300 frames never touch it.
actor ReplayVideoRenderer {
    static let shared = ReplayVideoRenderer()

    struct Plate: @unchecked Sendable {
        /// 1080 × 1920, the card without its canvas and caption.
        let background: CGImage
        /// The two slots, in PIXELS, top-left origin.
        let canvas: CGRect
        let caption: CGRect
        var captions: [ReplayCaption.State: CGImage]
        let renderer: ReplayCGRenderer
    }

    private static let log = Logger(subsystem: "app.onyx.health", category: "replay")

    /// One render per session AND content: the timeline is part of the key,
    /// so an edited session or late watch samples make a new video (review),
    /// and a second request while one is drawing awaits it instead of
    /// racing it for the same file.
    /// ponytail: in memory, per launch; a new launch re-renders once.
    private var renders: [String: (timeline: SessionReplay.Timeline, task: Task<URL, Error>)] = [:]

    func video(_ source: ReplaySource) async throws -> URL {
        if let known = renders[source.sessionId], known.timeline == source.timeline {
            return try await known.task.value
        }
        let task = Task { try await self.render(source) }
        renders[source.sessionId] = (source.timeline, task)
        do {
            return try await task.value
        } catch {
            if renders[source.sessionId]?.timeline == source.timeline { renders[source.sessionId] = nil }
            throw error
        }
    }

    private func render(_ source: ReplaySource) async throws -> URL {
        var plate = try await MainActor.run { try ReplayExporter.plate(source) }
        // One hop per line, so the main actor is never held for all of them.
        for state in ReplayCaption.states(source.timeline) {
            let width = plate.caption.width / ReplayExporter.scale
            if let image = await MainActor.run(body: { ReplayExporter.caption(source, state, width: width) }) {
                plate.captions[state] = image
            }
        }
        let out = try ReplayExporter.url(source, .video, "mp4")
        try await write(plate, timeline: source.timeline, to: out)
        return out
    }

    private func write(_ plate: Plate, timeline: SessionReplay.Timeline, to out: URL) async throws {
        try? FileManager.default.removeItem(at: out)
        let width = plate.background.width, height = plate.background.height
        let fps = ReplayExporter.fps
        let began = Date()

        let writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: fps,
            ] as [String: Any],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ])
        guard writer.canAdd(input) else { throw ReplayExporter.Failure.writer("cannot add the video input") }
        writer.add(input)
        guard writer.startWriting() else {
            throw ReplayExporter.Failure.writer(writer.error?.localizedDescription ?? "startWriting")
        }
        writer.startSession(atSourceTime: .zero)

        let frames = Int(timeline.duration * Double(fps))
        // Any exit that is not a finished file — a dismissed share sheet
        // (cancellation), a render or append failure — leaves no writer
        // running and no half-written file behind.
        defer {
            if writer.status == .writing {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: out)
            }
        }
        for i in 0..<frames {
            try Task.checkCancellation()
            while !input.isReadyForMoreMediaData {
                // A writer that failed (the encoder taken away when the app
                // went to the background) never becomes ready again (review).
                guard writer.status == .writing else {
                    throw ReplayExporter.Failure.writer(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")
                }
                try await Task.sleep(for: .milliseconds(4))
            }
            let t = timeline.duration * Double(i) / Double(frames - 1)
            guard let pool = adaptor.pixelBufferPool,
                  let buffer = Self.frame(plate, timeline: timeline, at: t, pool: pool)
            else { throw ReplayExporter.Failure.render }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps)) else {
                throw ReplayExporter.Failure.writer(writer.error?.localizedDescription ?? "append \(i)")
            }
        }
        input.markAsFinished()
        // The last (settled) frame is held to the 10 s mark instead of being
        // a zero-length sample at 9.97 s.
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frames), timescale: fps))
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw ReplayExporter.Failure.writer(writer.error?.localizedDescription ?? "finishWriting")
        }
        Self.log.notice("replay MP4 written off the main actor: \(frames) frames in \(Date().timeIntervalSince(began), format: .fixed(precision: 1)) s")
    }

    /// One frame: the plate, the canvas drawn into its slot, the caption line
    /// the frame shows.
    private static func frame(_ plate: Plate, timeline: SessionReplay.Timeline, at t: Double,
                              pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        let height = CGFloat(ctx.height)
        ctx.draw(plate.background, in: CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))

        let frame = timeline.frame(at: t)
        let scale = ReplayExporter.scale
        ctx.saveGState()
        // The renderer draws top-left, y down, in points.
        ctx.translateBy(x: plate.canvas.minX, y: height - plate.canvas.minY)
        ctx.scaleBy(x: scale, y: -scale)
        plate.renderer.draw(frame, in: ctx, size: CGSize(width: plate.canvas.width / scale, height: plate.canvas.height / scale))
        ctx.restoreGState()

        if let line = plate.captions[ReplayCaption.state(timeline, frame)] {
            let rect = CGRect(x: plate.caption.minX, y: height - plate.caption.minY - CGFloat(line.height),
                              width: CGFloat(line.width), height: CGFloat(line.height))
            ctx.draw(line, in: rect)
        }
        return buffer
    }
}

#if DEBUG
/// The shot loop's view of the share files (`session-share`, `session-share-bars`).
///
/// A screenshot of the share SHEET would review the system's UI; the claim
/// this wave makes is about the FILES. So the harness makes them through the
/// same prebake and actor the share button uses, draws the Stories PNG it
/// wrote, and logs the paths and timings (`ONYXREPLAY`) so the review can open
/// the originals.
struct ReplayShareHarness: View {
    let sessionId: String
    @Environment(AppEnvironment.self) private var environment
    @State private var image: UIImage?
    @State private var status = "Rendering…"

    var body: some View {
        VStack(spacing: OnyxSpace.s) {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            }
            Text(status).onyxType(.micro).foregroundStyle(Color.onyx.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .task { await export() }
    }

    private func export() async {
        let database = environment.database, id = sessionId
        guard let page = await Task.detached(operation: { SessionAnalysis.page(database: database, sessionId: id) }).value
        else { status = "no page for \(id)"; return }
        let samples = await environment.telemetry.reading(sessionId: id)?.samples ?? []
        let clocks = SessionReplay.Input.clocks(database: database, sessionId: id)
        let label = SessionAnalysis.dayLabel(page.report.session.dayKey, in: page.program) ?? "Session"
        let timeline = SessionReplay.timeline(.session(page, label: label, samples: samples, clocks: clocks))
        let source = ReplaySource(timeline: timeline, dayInk: Color.onyx.day(page.report.session.dayKey), sessionId: id,
                                  day: LogicalDay.date(fromISO: page.report.session.date) ?? timeline.masthead.startedAt)
        do {
            let prebakeBegan = Date()
            let set = await ReplayShareSet.prebake(source)
            let prebakeMs = Int(Date().timeIntervalSince(prebakeBegan) * 1000)
            image = set.items[1].file.flatMap { UIImage(contentsOfFile: $0.path) }
            status = "PNGs in \(prebakeMs) ms; rendering video off the main actor…"
            let began = Date()
            let video = try await ReplayVideoRenderer.shared.video(source)
            let seconds = Date().timeIntervalSince(began)
            status = String(format: "prebake %d ms · video %.1f s", prebakeMs, seconds)
            print("ONYXREPLAY square=\(set.items[0].file?.path ?? "") stories=\(set.items[1].file?.path ?? "") video=\(video.path) prebakeMs=\(prebakeMs) videoSeconds=\(seconds) message=\(set.message)")
        } catch {
            status = "export failed: \(error)"
            print("ONYXREPLAY failed \(error)")
        }
    }
}
#endif
