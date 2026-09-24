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
// therefore painted: the slab at 62 % over the backdrop, a 5 % white lift, a
// sheen down the top third and the one lit edge — the look `.onyxGlass` has
// over this backdrop, without the blur that has nothing to sample here anyway.
// ─────────────────────────────────────────────────────────────────────────────

/// One thing the share sheet offers.
struct ReplayShareItem: Transferable, Sendable {
    enum Kind: String, Sendable, CaseIterable { case square, stories, video }

    let kind: Kind
    let timeline: SessionReplay.Timeline
    let accent: Color
    let dayInk: Color
    let sessionId: String

    static func all(timeline: SessionReplay.Timeline, dayInk: Color, sessionId: String) -> [ReplayShareItem] {
        // The accent is read HERE, on the main actor, from the theme the page
        // is drawn in — the exporter must not re-read a global later.
        let accent = OnyxInk.Themed.accent
        return Kind.allCases.map {
            ReplayShareItem(kind: $0, timeline: timeline, accent: accent, dayInk: dayInk, sessionId: sessionId)
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

    var body: some View {
        let size = format.size
        VStack(spacing: 0) {
            Spacer(minLength: OnyxSpace.l)
            card
                .frame(width: size.width * 0.72)
            Spacer(minLength: OnyxSpace.l)
            wordmark
                .padding(.bottom, format == .stories ? OnyxSpace.l : OnyxSpace.l + OnyxSpace.xs)
        }
        .padding(.top, format.safeTop)
        .padding(.bottom, format.safeBottom)
        .frame(width: size.width, height: size.height)
        .background { backdrop }
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .large)
    }

    /// A deep two-stop radial of the theme accent over near-black, lit a
    /// little above the card's centre so the light falls ON the data.
    private var backdrop: some View {
        ZStack {
            Color.onyx.slab
            RadialGradient(
                colors: [accent.opacity(0.55), Color.onyx.slab.opacity(0)],
                center: UnitPoint(x: 0.5, y: format == .stories ? 0.42 : 0.4),
                startRadius: 0,
                endRadius: format.size.height * (format == .stories ? 0.62 : 0.78)
            )
        }
    }

    private var card: some View {
        let settle = frame.settle
        return VStack(alignment: .leading, spacing: OnyxSpace.m) {
            Text(timeline.masthead.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())
                .onyxType(.micro, tracking: 0.08)
                .fontWeight(.semibold)
                .foregroundStyle(Color.onyx.textSecondary)
            OnyxMasthead(timeline.masthead, accent: dayInk)
                // The masthead settles in the last second of the video; the
                // PNGs are the final frame, where it is simply there.
                .opacity(settle)
                .offset(y: 6 * (1 - settle))
            ReplayCanvas(timeline: timeline, frame: frame, accent: accent)
                .frame(height: format == .stories ? 132 : 92)
            ReplayCaption(timeline: timeline, frame: frame)
        }
        .padding(OnyxSpace.l)
        .background { frost }
    }

    /// The Stone slab, painted (see the file header).
    private var frost: some View {
        let shape = RoundedRectangle(cornerRadius: OnyxCorner.tile, style: .continuous)
        return shape
            .fill(Color.onyx.slab.opacity(0.62))
            .overlay { shape.fill(.white.opacity(0.05)) }
            .overlay {
                shape.fill(LinearGradient(
                    stops: [.init(color: .white.opacity(0.07), location: 0), .init(color: .white.opacity(0), location: 0.35)],
                    startPoint: .top, endPoint: .bottom
                ))
            }
            .overlay {
                shape.strokeBorder(LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.18), location: 0),
                        .init(color: .white.opacity(0.05), location: 0.3),
                        .init(color: .white.opacity(0.05), location: 1),
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
        .opacity(0.9)
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
        let name = timelineSlug(item.timeline) + "-" + item.kind.rawValue
        return folder.appending(path: "\(name).\(ext)")
    }

    private static func timelineSlug(_ timeline: SessionReplay.Timeline) -> String {
        let day = timeline.masthead.startedAt.formatted(.iso8601.year().month().day())
        let name = timeline.masthead.name.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return "onyx-\(String(name).split(separator: "-").joined(separator: "-"))-\(day)"
    }

    private static func renderer(_ item: ReplayShareItem, format: ReplayShareFrame.Format, at t: Double) -> ImageRenderer<ReplayShareFrame> {
        let renderer = ImageRenderer(content: ReplayShareFrame(
            format: format, timeline: item.timeline, frame: item.timeline.frame(at: t),
            accent: item.accent, dayInk: item.dayInk
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
        for i in 0...frames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(4))
            }
            let t = Double(i) / Double(fps)
            guard let image = renderer(item, format: .stories, at: t).cgImage,
                  let pool = adaptor.pixelBufferPool,
                  let buffer = pixelBuffer(from: image, pool: pool)
            else {
                writer.cancelWriting()
                throw Failure.render
            }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps)) else {
                writer.cancelWriting()
                throw Failure.writer(writer.error?.localizedDescription ?? "append \(i)")
            }
            // One frame per turn: the share sheet is on this actor too.
            await Task.yield()
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw Failure.writer(writer.error?.localizedDescription ?? "finishWriting")
        }
        log.notice("replay MP4 written: \(frames + 1) frames in \(Date().timeIntervalSince(began), format: .fixed(precision: 1)) s")
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
        let items = ReplayShareItem.all(timeline: timeline, dayInk: Color.onyx.day(page.report.session.dayKey), sessionId: id)
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
