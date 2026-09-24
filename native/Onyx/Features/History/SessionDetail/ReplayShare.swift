import SwiftUI
import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers
import OnyxUI
import OnyxCore
import os

// ─────────────────────────────────────────────────────────────────────────────
// The replay, shared (overhaul W5, founder challenge F2): a 1080×1080 PNG, a
// 1080×1920 Stories PNG, and a ten-second 1080×1920 MP4 — all the same frame
// view (`ReplayShareFrame`) of the same `SessionReplay.Timeline`.
//
// ── RENDERED WHEN ASKED FOR, NOT WHEN THE PAGE OPENS ────────────────────────
// Each item is a `FileRepresentation` whose file is made in its exporting
// closure, so nothing is rendered until the share sheet asks for that item: a
// History browse never pays for 300 frames of video. `exportingCondition` keeps
// the PNG items from offering a movie and the movie from offering a PNG.
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

/// One thing the share sheet offers.
struct ReplayShareItem: Transferable, Sendable {
    enum Kind: String, Sendable, CaseIterable { case square, stories, video }

    let kind: Kind
    let timeline: SessionReplay.Timeline
    let accent: Color
    let dayInk: Color
    let sessionId: String
    /// The session's logical day — what the page's title says.
    let day: Date

    static func all(timeline: SessionReplay.Timeline, dayInk: Color, sessionId: String, day: Date) -> [ReplayShareItem] {
        // The accent is read HERE, on the main actor, from the theme the page
        // is drawn in — the exporter must not re-read a global later.
        let accent = OnyxInk.Themed.accent
        return Kind.allCases.map {
            ReplayShareItem(kind: $0, timeline: timeline, accent: accent, dayInk: dayInk, sessionId: sessionId, day: day)
        }
    }

    var title: String {
        switch kind {
        case .square: "\(timeline.masthead.name) — square"
        case .stories: "\(timeline.masthead.name) — Stories"
        case .video: "\(timeline.masthead.name) — replay video"
        }
    }

    var symbol: String {
        switch kind {
        case .square: "square"
        case .stories: "rectangle.portrait"
        case .video: "play.rectangle"
        }
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { item in
            SentTransferredFile(try await ReplayExporter.png(item))
        }
        .exportingCondition { $0.kind != .video }
        FileRepresentation(exportedContentType: .mpeg4Movie) { item in
            SentTransferredFile(try await ReplayExporter.video(item))
        }
        .exportingCondition { $0.kind == .video }
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

    /// The card's own surface, flattened — the ring each dot is cut out with.
    private static let cardInk = Color.onyx.slab.mix(with: .white, by: 0.08)

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
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .large)
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
            OnyxMasthead(timeline.masthead(at: frame), accent: dayInk)
            ReplayCanvas(timeline: timeline, frame: frame, accent: accent,
                         lineWidth: 2.5, ground: Self.cardInk)
                .frame(height: format == .stories ? 170 : 96)
            ReplayCaption(timeline: timeline, frame: frame)
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

/// Makes the files. Main actor because `ImageRenderer` is.
@MainActor
enum ReplayExporter {
    /// 360 × 640 points → 1080 × 1920 pixels.
    nonisolated static let scale: CGFloat = 3
    nonisolated static let fps: Int32 = 30

    enum Failure: Error { case render, writer(String) }

    private static let log = Logger(subsystem: "app.onyx.health", category: "replay")

    private static func url(_ item: ReplayShareItem, _ ext: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "replay", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // A readable name: it is the file name the recipient sees.
        let name = slug(item) + "-" + item.kind.rawValue
        return folder.appending(path: "\(name).\(ext)")
    }

    private static func slug(_ item: ReplayShareItem) -> String {
        let day = LogicalDay.iso(item.day)
        let name = item.timeline.masthead.name.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return "onyx-\(String(name).split(separator: "-").joined(separator: "-"))-\(day)"
    }

    private static func renderer(_ item: ReplayShareItem, format: ReplayShareFrame.Format, at t: Double) -> ImageRenderer<ReplayShareFrame> {
        let renderer = ImageRenderer(content: ReplayShareFrame(
            format: format, timeline: item.timeline, frame: item.timeline.frame(at: t),
            accent: item.accent, dayInk: item.dayInk, day: item.day
        ))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(format.size)
        return renderer
    }

    /// The final frame as a PNG — `square` at 1080², `stories` at 1080 × 1920.
    static func png(_ item: ReplayShareItem) throws -> URL {
        let format: ReplayShareFrame.Format = item.kind == .square ? .square : .stories
        guard let data = renderer(item, format: format, at: item.timeline.duration).uiImage?.pngData()
        else { throw Failure.render }
        let out = try url(item, "png")
        try data.write(to: out, options: .atomic)
        log.notice("replay \(item.kind.rawValue, privacy: .public) PNG written: \(data.count) bytes")
        return out
    }

    /// Ten seconds at 30 fps, H.264, 1080 × 1920 — every frame the Stories
    /// frame at `t = i / 30`.
    ///
    /// ponytail: re-rendered on every share (≈ 300 `ImageRenderer` passes,
    /// yielding between frames so the share sheet stays live); cache by a
    /// timeline hash if people share the same session repeatedly.
    static func video(_ item: ReplayShareItem) async throws -> URL {
        let out = try url(item, "mp4")
        try? FileManager.default.removeItem(at: out)
        let size = ReplayShareFrame.Format.stories.size
        let width = Int(size.width * scale), height = Int(size.height * scale)
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
        guard writer.canAdd(input) else { throw Failure.writer("cannot add the video input") }
        writer.add(input)
        guard writer.startWriting() else { throw Failure.writer(writer.error?.localizedDescription ?? "startWriting") }
        writer.startSession(atSourceTime: .zero)

        let frames = Int(item.timeline.duration * Double(fps))
        // Any exit that is not a finished file — a dismissed share sheet
        // (cancellation), a render or append failure — leaves no writer
        // running and no half-written file behind (review).
        defer {
            if writer.status == .writing {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: out)
            }
        }
        for i in 0..<frames {
            try Task.checkCancellation()
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(4))
            }
            let t = item.timeline.duration * Double(i) / Double(frames - 1)
            guard let image = renderer(item, format: .stories, at: t).cgImage,
                  let pool = adaptor.pixelBufferPool,
                  let buffer = pixelBuffer(from: image, pool: pool)
            else { throw Failure.render }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps)) else {
                throw Failure.writer(writer.error?.localizedDescription ?? "append \(i)")
            }
            // One frame per turn: the share sheet is on this actor too.
            await Task.yield()
        }
        input.markAsFinished()
        // The last (settled) frame is held to the 10 s mark instead of being
        // a zero-length sample at 9.97 s.
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frames), timescale: fps))
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw Failure.writer(writer.error?.localizedDescription ?? "finishWriting")
        }
        log.notice("replay MP4 written: \(frames) frames in \(Date().timeIntervalSince(began), format: .fixed(precision: 1)) s")
        return out
    }

    private static func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        return buffer
    }
}

#if DEBUG
/// The shot loop's view of the share files (`session-share`, `session-share-bars`).
///
/// A screenshot of the share SHEET would review the system's UI; the claim
/// this wave makes is about the FILES. So the harness writes all three through
/// the same exporter the share sheet calls, draws the Stories PNG it wrote, and
/// logs the paths (`ONYXREPLAY`) so the review can open the originals.
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
        let items = ReplayShareItem.all(timeline: timeline, dayInk: Color.onyx.day(page.report.session.dayKey), sessionId: id,
                                        day: LogicalDay.date(fromISO: page.report.session.date) ?? timeline.masthead.startedAt)
        do {
            let square = try ReplayExporter.png(items[0])
            let stories = try ReplayExporter.png(items[1])
            image = UIImage(contentsOfFile: stories.path)
            status = "PNGs written; rendering video…"
            let began = Date()
            let video = try await ReplayExporter.video(items[2])
            let seconds = Date().timeIntervalSince(began)
            status = String(format: "video %.1f s", seconds)
            print("ONYXREPLAY square=\(square.path) stories=\(stories.path) video=\(video.path) seconds=\(seconds)")
        } catch {
            status = "export failed: \(error)"
            print("ONYXREPLAY failed \(error)")
        }
    }
}
#endif
