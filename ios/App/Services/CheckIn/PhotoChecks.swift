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
