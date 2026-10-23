import CoreGraphics
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
}
