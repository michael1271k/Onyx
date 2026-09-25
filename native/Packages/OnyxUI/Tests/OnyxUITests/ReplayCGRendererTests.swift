import Testing
import SwiftUI
import OnyxCore
@testable import OnyxUI

/// Precision B5 — the MP4 is drawn by `ReplayCGRenderer` (CoreGraphics, off
/// the main actor), the summary and the PNGs by `ReplayCanvas` (SwiftUI). Two
/// drawings of one frame are how a video comes to disagree with its poster,
/// so the CG port is held to the canvas: the same frame, rendered both ways,
/// differs in at most 2 % of its pixels.
///
/// Fails if the port drifts from the canvas — a plot inset, a dot radius, the
/// y flip, the bar's height or a colour taken from the wrong ink.
@MainActor
@Suite("Replay — the CoreGraphics renderer draws what the canvas draws")
struct ReplayCGRendererTests {

    static let start = Date(timeIntervalSince1970: 1_790_000_000)

    static func timeline(hr: Bool) -> SessionReplay.Timeline {
        let end = start.addingTimeInterval(3_600)
        let masthead = SessionMasthead(name: "Upper A", durationSec: 3_600, tonnageKg: 8_450, avgBpm: 131,
                                       prCount: 3, hrSpark: [], startedAt: start)
        let movements = [
            SessionReplay.Movement(name: "Incline DB Press", tonnageKg: 2_400),
            SessionReplay.Movement(name: "Chest Supported Row", tonnageKg: 3_000),
            SessionReplay.Movement(name: "Cable Pushdown", tonnageKg: 900),
        ]
        func at(_ minute: Double) -> Date { start.addingTimeInterval(minute * 60) }
        let sets = [
            SessionReplay.SetMark(movement: 0, at: at(4)),
            SessionReplay.SetMark(movement: 0, at: at(8), records: 2),
            SessionReplay.SetMark(movement: 1, at: at(20)),
            SessionReplay.SetMark(movement: 1, at: at(30), records: 1),
            SessionReplay.SetMark(movement: 2, at: at(40)),
            SessionReplay.SetMark(movement: 2, at: at(50)),
        ]
        let samples = hr
            ? stride(from: 0.0, to: 3_600, by: 20).map {
                HRSample(at: start.addingTimeInterval($0), bpm: Int(110 + 25 * sin($0 / 300)))
            }
            : []
        return SessionReplay.timeline(SessionReplay.Input(
            masthead: masthead, start: start, end: end, samples: samples, movements: movements, sets: sets
        ))
    }

    /// RGBA8 pixels of an image, drawn into a buffer of `width × height`.
    static func pixels(_ image: CGImage, width: Int, height: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width * height * 4)
        out.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return out
    }

    @Test("t = 0 / 5 / 10 s, with and without heart rate: ≤ 2 % of pixels differ",
          arguments: [(0.0, true), (5.0, true), (10.0, true), (0.0, false), (5.0, false), (10.0, false)])
    func matchesTheCanvas(t: Double, hr: Bool) throws {
        let timeline = Self.timeline(hr: hr)
        let frame = timeline.frame(at: t)
        let size = CGSize(width: 300, height: 120)
        let scale: CGFloat = 2
        let accent = Color.onyx.good
        let ground = Color.onyx.slab

        let swiftUI = ImageRenderer(content:
            ReplayCanvas(timeline: timeline, frame: frame, accent: accent, lineWidth: 2.5, ground: ground)
                .frame(width: size.width, height: size.height)
                .background(ground)
        )
        swiftUI.scale = scale
        let a = try #require(swiftUI.cgImage)

        let renderer = ReplayCGRenderer(timeline: timeline, accent: accent, lineWidth: 2.5, ground: ground)
        let b = try #require(renderer.image(frame, size: size, scale: scale, background: ground))

        let w = Int(size.width * scale), h = Int(size.height * scale)
        let pa = Self.pixels(a, width: w, height: h), pb = Self.pixels(b, width: w, height: h)
        var differing = 0
        for i in stride(from: 0, to: pa.count, by: 4) {
            let delta = (0..<3).map { abs(Int(pa[i + $0]) - Int(pb[i + $0])) }.max() ?? 0
            if delta > 32 { differing += 1 }
        }
        let share = Double(differing) / Double(w * h)
        #expect(share <= 0.02, "t=\(t) hr=\(hr): \(Int(share * 1000) / 10)% of pixels differ")
    }
}
