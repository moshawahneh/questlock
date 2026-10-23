// Scores Apple's on-device photo check against labelled photos, to tune the thresholds in
// ios/App/Services/CheckIn/PhotoChecks.swift and supabase/functions/_shared/decision.ts.
// Run: tools/eval-photos/run.sh   (compiles this file together with the app's PhotoChecks.swift)
import CoreGraphics
import Foundation
import ImageIO

struct Case: Decodable {
    let photo: String          // back photo, in eval/photos/
    let front: String?         // optional front photo; without one, a face is assumed
    let target: String         // target key, e.g. "bench"
    let expect: String         // accept | target_not_seen | looks_like_screen | no_face
    let note: String?
}

/// Loads a photo upright and at most 1024 px on the long side, like the app does before checking.
func load(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 1024,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "eval")
let casesURL = root.appendingPathComponent("cases.json")
guard let data = try? Data(contentsOf: casesURL),
      let cases = try? JSONDecoder().decode([Case].self, from: data) else {
    print("Couldn't read \(casesURL.path). Copy eval/cases.example.json to eval/cases.json and list your photos.")
    exit(1)
}

var rows: [(Case, PhotoObservations, CheckInDecision.Verdict)] = []
for item in cases {
    let backURL = root.appendingPathComponent("photos").appendingPathComponent(item.photo)
    guard let back = load(backURL) else { print("⚠️  can't open \(item.photo)"); continue }
    let front = item.front.flatMap { load(root.appendingPathComponent("photos").appendingPathComponent($0)) }
    var observations = PhotoClassifier.observe(front: front ?? back, back: back, targetKey: item.target)
    if front == nil { observations.front_has_face = true }
    rows.append((item, observations, CheckInDecision.verdict(observations)))
}

func pad(_ s: String, _ n: Int) -> String { s.count >= n ? String(s.prefix(n)) : s + String(repeating: " ", count: n - s.count) }
print(pad("", 2) + pad("photo", 26) + pad("target", 20) + pad("expected", 18) + pad("got", 18) + pad("target", 8) + pad("screen", 8) + "top labels")
for (item, o, verdict) in rows {
    let ok = verdict.rawValue == item.expect
    print((ok ? "✓ " : "✗ ") + pad(item.photo, 26) + pad(item.target, 20) + pad(item.expect, 18) + pad(verdict.rawValue, 18)
          + pad(String(format: "%.2f", o.target_confidence), 8) + pad(String(format: "%.2f", o.screen_confidence), 8)
          + o.top_labels.joined(separator: " "))
}

// Confusion matrix: should it have been accepted, and was it?
let shouldAccept = rows.filter { $0.0.expect == "accept" }
let shouldReject = rows.filter { $0.0.expect != "accept" }
let tp = shouldAccept.filter { $0.2 == .accept }.count
let fn = shouldAccept.count - tp
let fp = shouldReject.filter { $0.2 == .accept }.count
let tn = shouldReject.count - fp
let screenLeaks = rows.filter { $0.0.expect == "looks_like_screen" && $0.2 == .accept }.count
let exact = rows.filter { $0.2.rawValue == $0.0.expect }.count
print("""

    Accepted when it should be (true positive):   \(tp)
    Rejected but was real (false negative):       \(fn)
    Accepted but shouldn't be (false positive):   \(fp)
    Rejected when it should be (true negative):   \(tn)
    Screen photos let through:                    \(screenLeaks)  (target: 0)
    Correct overall: \(exact)/\(rows.count) = \(rows.isEmpty ? 0 : 100 * exact / rows.count)%  (target: ≥ 80%)
    """)

// Hints for tuning: where the real targets sit vs. the wrong objects and screens.
let realTarget = shouldAccept.map(\.1.target_confidence)
let wrongObject = rows.filter { $0.0.expect == "target_not_seen" }.map(\.1.target_confidence)
let screens = rows.filter { $0.0.expect == "looks_like_screen" }.map(\.1.screen_confidence)
let realScreen = shouldAccept.map(\.1.screen_confidence)
if let lo = realTarget.min() { print("Lowest target confidence on a real target:   \(String(format: "%.2f", lo))  (threshold \(CheckInDecision.minTargetConfidence))") }
if let hi = wrongObject.max() { print("Highest target confidence on a wrong object: \(String(format: "%.2f", hi))") }
if let lo = screens.min() { print("Lowest screen confidence on a screen photo:  \(String(format: "%.2f", lo))  (threshold \(CheckInDecision.maxScreenConfidence))") }
if let hi = realScreen.max() { print("Highest screen confidence on a real photo:   \(String(format: "%.2f", hi))") }
