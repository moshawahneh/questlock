import CoreGraphics
import Foundation
import Testing
@testable import QuestLock

/// The phone's copy of the decision rule (the server's copy, decision.ts, has the same cases in Deno).
struct PhotoChecksTests {
    static let good = PhotoObservations(front_has_face: true, target_confidence: 0.62, target_label: "bench",
                                        screen_confidence: 0.02, top_labels: ["bench:0.62"])

    @Test func clearPhotoIsAccepted() {
        #expect(CheckInDecision.verdict(Self.good) == .accept)
    }

    @Test func eachFailedCheckHasItsOwnReason() {
        var noFace = Self.good; noFace.front_has_face = false
        var screen = Self.good; screen.screen_confidence = 0.4
        var missing = Self.good; missing.target_confidence = 0.1
        #expect(CheckInDecision.verdict(noFace) == .noFace)
        #expect(CheckInDecision.verdict(screen) == .looksLikeScreen)
        #expect(CheckInDecision.verdict(missing) == .targetNotSeen)
    }

    @Test func screenBeatsAClearTarget() {
        var benchOnLaptop = Self.good
        benchOnLaptop.target_confidence = 0.9
        benchOnLaptop.screen_confidence = 0.5
        #expect(CheckInDecision.verdict(benchOnLaptop) == .looksLikeScreen)
    }

    @Test func thresholdEdges() {
        var o = Self.good
        o.target_confidence = CheckInDecision.minTargetConfidence
        #expect(CheckInDecision.verdict(o) == .accept)
        o.screen_confidence = CheckInDecision.maxScreenConfidence
        #expect(CheckInDecision.verdict(o) == .looksLikeScreen)
    }

    @Test func everyTargetHasLabels() {
        for key in ["tree", "bench", "street_sign", "post_box", "bicycle", "lamp_post", "statue_or_monument",
                    "building_entrance", "shop_front", "traffic_light", "fence", "plant"] {
            #expect(!(TargetLabels.accepted[key] ?? []).isEmpty, "no labels for \(key)")
        }
    }

    @Test func aPlainPatternIsNotABench() {
        let observations = PhotoClassifier.observe(front: ImageProcessingTests.checkerboard,
                                                   back: ImageProcessingTests.checkerboard, targetKey: "bench")
        #expect(!observations.front_has_face)
        #expect(observations.target_confidence < CheckInDecision.minTargetConfidence)
        #expect(CheckInDecision.verdict(observations) != .accept)
    }

    // MARK: - Screen pixel pattern

    static func rgbImage(_ size: Int, _ colour: (Int, Int) -> (Double, Double, Double)) -> CGImage {
        var px = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let (r, g, b) = colour(x, y), i = 4 * (y * size + x)
                px[i] = UInt8(max(0, min(255, r * 255)))
                px[i + 1] = UInt8(max(0, min(255, g * 255)))
                px[i + 2] = UInt8(max(0, min(255, b * 255)))
            }
        }
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: CGDataProvider(data: Data(px) as CFData)!, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    /// A soft picture: what a photo of a real object looks like at the pixel level.
    static func scene(_ x: Int, _ y: Int) -> Double { 0.45 + 0.25 * sin(Double(x) / 150) * cos(Double(y) / 110) }

    @Test func screenSubpixelGridScoresHigh() {
        // Red, green and blue columns every 3 pixels with a dark line every 3rd row: a laptop screen up close.
        let screen = Self.rgbImage(1024) { x, y in
            let s = Self.scene(x, y), gap = y % 3 == 2 ? 0.55 : 1.0
            switch x % 3 {
            case 0: return (s * gap * 1.6, s * 0.3, s * 0.3)
            case 1: return (s * 0.3, s * gap * 1.6, s * 0.3)
            default: return (s * 0.3, s * 0.3, s * gap * 1.6)
            }
        }
        let scores = ScreenPattern.scores(screen)
        #expect(scores.peak > 5)
        #expect(scores.chroma > 2)
    }

    @Test func realLookingImagesScoreLow() {
        var seed: UInt64 = 7
        func noise() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) - 0.5 }
        // Real photos always carry a little sensor noise (here 2%). Perfectly clean synthetic stripes would
        // score high: rounding a perfect wave to 8-bit pixels adds fine regular ripples of its own.
        let soft = Self.rgbImage(1024) { x, y in let s = Self.scene(x, y) + 0.04 * noise(); return (s, s * 0.95, s * 0.9) }
        let edges = Self.rgbImage(1024) { x, y in let s = ((x / 300 + y / 260) % 2 == 0 ? 0.3 : 0.7) + 0.02 * noise(); return (s, s, s) }
        let stripes = Self.rgbImage(1024) { x, _ in let s = 0.5 + 0.3 * sin(Double(x) * 2 * .pi / 40) + 0.02 * noise(); return (s, s, s) }
        for image in [soft, edges, stripes] {
            #expect(ScreenPattern.scores(image).peak < 3)
        }
    }

    @Test func imagesSmallerThanATileScoreZero() {
        #expect(ScreenPattern.scores(ImageProcessingTests.checkerboard) == .zero) // 64×64
    }
}

