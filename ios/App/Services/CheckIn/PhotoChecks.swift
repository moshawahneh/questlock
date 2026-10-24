import Accelerate
import CoreGraphics
import Foundation
import Vision

// On-device photo checks with Apple's Vision framework: is there a face in the front photo, is the
// target in the back photo, and does the back photo look like a picture of a screen?
//
// Platform-neutral on purpose (Foundation + CoreGraphics + Vision only): the Mac tuning tool in
// tools/eval-photos compiles this same file, so it measures exactly what the app does.
// See docs/decisions/004-apple-vision-instead-of-claude.md.

/// What the phone saw. These are the facts sent to verify-checkin, which makes the final decision.
struct PhotoObservations: Codable, Equatable, Sendable {
    var front_has_face: Bool
    /// Highest confidence (0–1) among the classifier labels that count as the target.
    var target_confidence: Double
    var target_label: String?
    /// Highest confidence among labels that suggest a photo of a screen.
    var screen_confidence: Double
    /// Top labels for the record, e.g. "bench:0.62".
    var top_labels: [String]
}

/// Apple classifier labels accepted for each target. The keys must match TARGETS in
/// supabase/functions/_shared/targets.ts.
enum TargetLabels {
    static let accepted: [String: [String]] = [
        "tree": ["tree", "oak_tree", "maple_tree", "palm_tree", "eucalyptus_tree", "christmas_tree"],
        "bench": ["bench"],
        "street_sign": ["street_sign", "sign"],
        "post_box": ["mailbox"],
        "bicycle": ["bicycle"],
        "lamp_post": ["lamppost"],
        "statue_or_monument": ["statue", "monument"],
        "building_entrance": ["door"],
        "shop_front": ["storefront"],
        "traffic_light": ["traffic_light"],
        "fence": ["fence"],
        "plant": ["plant", "decorative_plant"],
        // Test-only target (used for the first indoor test on 23 Oct 2026).
        "water_bottle": ["bottle"],
    ]

    /// Labels that suggest the "target" is a picture on a screen rather than the real thing.
    static let screen: [String] = ["screenshot", "computer_monitor", "television", "laptop", "computer", "phone"]
}

/// The decision rule, mirrored from supabase/functions/_shared/decision.ts (the server's copy is the
/// one that counts). The phone uses it to warn before uploading, so a bad photo doesn't use an attempt.
enum CheckInDecision {
    /// Provisional thresholds: tune them with tools/eval-photos on real check-in photos.
    static let minTargetConfidence = 0.3
    static let maxScreenConfidence = 0.3

    enum Verdict: String, Equatable, Sendable {
        case accept
        case noFace = "no_face"
        case targetNotSeen = "target_not_seen"
        case looksLikeScreen = "looks_like_screen"
    }

    static func verdict(_ o: PhotoObservations) -> Verdict {
        if !o.front_has_face { return .noFace }
        if o.screen_confidence >= maxScreenConfidence { return .looksLikeScreen }
        if o.target_confidence < minTargetConfidence { return .targetNotSeen }
        return .accept
    }
}

enum FaceCheck {
    /// True if Vision finds at least one face. Synchronous and slow-ish: call it off the main thread.
    static func containsFace(_ image: CGImage) -> Bool {
        let request = VNDetectFaceRectanglesRequest()
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        } catch {
            return false
        }
        return !(request.results ?? []).isEmpty
    }
}

enum PhotoClassifier {
    /// Every label Apple's classifier gives the image, with its confidence (0–1). Labels aren't exclusive:
    /// "outdoor" and "bench" can both be high. Synchronous: call it off the main thread.
    static func classify(_ image: CGImage) -> [String: Double] {
        let request = VNClassifyImageRequest()
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        } catch {
            return [:]
        }
        var result: [String: Double] = [:]
        for observation in request.results ?? [] where observation.confidence > 0.01 {
            result[observation.identifier] = Double(observation.confidence)
        }
        return result
    }

    /// The observations for one check-in. `front` and `back` must already be upright.
    static func observe(front: CGImage, back: CGImage, targetKey: String) -> PhotoObservations {
        let labels = classify(back)
        let accepted = TargetLabels.accepted[targetKey] ?? []
        let best = accepted.compactMap { label in labels[label].map { (label, $0) } }.max { $0.1 < $1.1 }
        let screen = TargetLabels.screen.compactMap { labels[$0] }.max() ?? 0
        let top = labels.sorted { $0.value > $1.value }.prefix(5).map { "\($0.key):\(String(format: "%.2f", $0.value))" }
        return PhotoObservations(
            front_has_face: FaceCheck.containsFace(front),
            target_confidence: best?.1 ?? 0,
            target_label: best?.0,
            screen_confidence: screen,
            top_labels: Array(top)
        )
    }
}

/// Looks for a screen's pixel grid in a full-resolution photo. Close up, a photo of a screen carries a
/// fine regular pattern from the screen's pixels (and often rainbow "moiré" fringes). Real objects don't.
/// This catches the case the classifier misses: a target on a screen that fills the whole frame.
///
/// Measured, not yet trusted: tools/eval-photos prints both scores so the thresholds can be set from
/// real photos before the decision rule uses them.
enum ScreenPattern {
    struct Scores: Codable, Equatable, Sendable {
        /// Strongest isolated spike in the photo's averaged frequency spectrum, in natural-log units
        /// above its neighbours (3 ≈ 20× stronger). A pixel grid makes sharp spikes; real scenes don't.
        var peak: Double
        /// Fine colour detail divided by fine brightness detail. Moiré makes rainbow fringes; real photos
        /// have little fine colour detail (cameras smooth colour more than brightness).
        var chroma: Double

        static let zero = Scores(peak: 0, chroma: 0)
    }

    static let tileSize = 512                 // FFT size (2^9)
    static let bandLow = 0.10                 // cycles per pixel: ignore coarse textures (fences, blinds)
    static let bandHigh = 0.45                // stop short of the sensor's own limit (0.5)

    /// `image` must be the full-resolution photo: downscaling would blur away the pattern.
    /// Uses up to 3×3 tiles of 512×512 around the centre. Smaller images score zero.
    static func scores(_ image: CGImage) -> Scores {
        let n = tileSize, log2n = vDSP_Length(9)
        guard image.width >= n, image.height >= n,
              let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return .zero }
        defer { vDSP_destroy_fftsetup(setup) }

        let cols = min(3, image.width / n), rows = min(3, image.height / n)
        let x0 = (image.width - cols * n) / 2, y0 = (image.height - rows * n) / 2
        let window = hann(n)
        var power = [Float](repeating: 0, count: n * n)    // averaged over tiles (Welch's method)
        var lumaDetail = 0.0, colourDetail = 0.0
        var tiles = 0

        for row in 0..<rows {
            for col in 0..<cols {
                let rect = CGRect(x: x0 + col * n, y: y0 + row * n, width: n, height: n)
                guard let tile = image.cropping(to: rect), let rgba = pixels(tile, size: n) else { continue }
                var luma = [Float](repeating: 0, count: n * n)
                var cb = [Float](repeating: 0, count: n * n)
                var cr = [Float](repeating: 0, count: n * n)
                for i in 0..<(n * n) {
                    let r = Float(rgba[4 * i]), g = Float(rgba[4 * i + 1]), b = Float(rgba[4 * i + 2])
                    let y = 0.299 * r + 0.587 * g + 0.114 * b
                    luma[i] = y
                    cb[i] = b - y
                    cr[i] = r - y
                }
                lumaDetail += laplacianEnergy(luma, size: n)
                colourDetail += laplacianEnergy(cb, size: n) + laplacianEnergy(cr, size: n)

                // Windowed, mean-removed brightness → 2D FFT → power, accumulated across tiles.
                var mean: Float = 0
                vDSP_meanv(luma, 1, &mean, vDSP_Length(n * n))
                for y in 0..<n {
                    for x in 0..<n { luma[y * n + x] = (luma[y * n + x] - mean) * window[x] * window[y] }
                }
                var imaginary = [Float](repeating: 0, count: n * n)
                luma.withUnsafeMutableBufferPointer { re in
                    imaginary.withUnsafeMutableBufferPointer { im in
                        var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                        vDSP_fft2d_zip(setup, &split, 1, 0, log2n, log2n, FFTDirection(kFFTDirection_Forward))
                    }
                }
                for i in 0..<(n * n) { power[i] += luma[i] * luma[i] + imaginary[i] * imaginary[i] }
                tiles += 1
            }
        }
        guard tiles > 0 else { return .zero }

        let logPower = power.map { log($0 / Float(tiles) + 1e-6) }
        let peak = strongestIsolatedPeak(logPower, size: n)
        return Scores(peak: Double(peak), chroma: lumaDetail > 0 ? colourDetail / lumaDetail : 0)
    }

    /// The largest amount by which a frequency bin in the band beats its four neighbours 3 bins away
    /// (towards/away from the centre and to either side). A pixel grid gives an isolated point. The
    /// straight edges of real objects give lines through the centre, which fail the towards/away test.
    static func strongestIsolatedPeak(_ logPower: [Float], size n: Int) -> Float {
        func at(_ u: Int, _ v: Int) -> Float { logPower[((v % n + n) % n) * n + ((u % n + n) % n)] }
        let low = Float(bandLow) * Float(n), high = Float(bandHigh) * Float(n), d: Float = 3
        var best: Float = 0
        for v in 0..<(n / 2) {                      // the spectrum of a real image is symmetric: half is enough
            for index in 0..<n {
                let u = index < n / 2 ? index : index - n
                // Compression blocks (HEIC/JPEG) make spikes on the axes at multiples of 1/32 cycle/pixel.
                if abs(v) <= 1 && abs(u) % 16 <= 1 || abs(u) <= 1 && abs(v) % 16 <= 1 { continue }
                let radius = (Float(u * u + v * v)).squareRoot()
                guard radius >= low, radius < high else { continue }
                let du = Float(u) / radius, dv = Float(v) / radius
                func neighbour(_ x: Float, _ y: Float) -> Float {
                    at(Int((Float(u) + d * x).rounded()), Int((Float(v) + d * y).rounded()))
                }
                let around = max(neighbour(du, dv), neighbour(-du, -dv), neighbour(-dv, du), neighbour(dv, -du))
                best = max(best, at(u, v) - around)
            }
        }
        return best
    }

    private static func hann(_ n: Int) -> [Float] {
        (0..<n).map { 0.5 - 0.5 * cos(2 * Float.pi * Float($0) / Float(n - 1)) }
    }

    /// Mean squared Laplacian: how much fine (pixel-to-pixel) detail a channel has.
    private static func laplacianEnergy(_ channel: [Float], size n: Int) -> Double {
        var sum = 0.0
        for y in 1..<(n - 1) {
            for x in 1..<(n - 1) {
                let i = y * n + x
                let lap = 4 * channel[i] - channel[i - 1] - channel[i + 1] - channel[i - n] - channel[i + n]
                sum += Double(lap * lap)
            }
        }
        return sum / Double((n - 2) * (n - 2))
    }

    /// The tile's pixels as RGBA bytes, copied 1:1 (no resampling, which would destroy the pattern).
    private static func pixels(_ image: CGImage, size n: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        return ok ? bytes : nil
    }
}
