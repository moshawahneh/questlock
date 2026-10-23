import CoreGraphics
import Testing
import UIKit
@testable import QuestLock

struct ImageProcessingTests {
    /// A grey image whose brightness at (x, y) comes from `shade` (0…1).
    static func image(width: Int = 64, height: Int = 64, _ shade: (Int, Int) -> Double) -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels[y * width + x] = UInt8(max(0, min(255, shade(x, y) * 255)))
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    // Kept between 20% and 80% grey: pure black/white edges get flattened when resampled to 9×8.
    static let leftToRight = image { x, _ in 0.2 + 0.6 * Double(x) / 63 }       // brighter to the right
    static let rightToLeft = image { x, _ in 0.8 - 0.6 * Double(x) / 63 }       // brighter to the left
    static let checkerboard = image { x, y in ((x / 8 + y / 8) % 2 == 0) ? 0.1 : 0.9 }

    @Test func identicalImagesHaveDistanceZero() throws {
        let a = try #require(PerceptualHash.dHash(Self.checkerboard))
        let b = try #require(PerceptualHash.dHash(Self.checkerboard))
        #expect(PerceptualHash.hammingDistance(a, b) == 0)
    }

    @Test func oppositeGradientsDifferInEveryBit() throws {
        let rising = try #require(PerceptualHash.dHash(Self.leftToRight))
        let falling = try #require(PerceptualHash.dHash(Self.rightToLeft))
        #expect(rising == 0)                 // left is never brighter than right
        #expect(falling == UInt64.max)       // left is always brighter than right
        #expect(PerceptualHash.hammingDistance(rising, falling) == 64)
    }

    @Test func slightlyBrighterCopyStaysClose() throws {
        let original = try #require(PerceptualHash.dHash(Self.checkerboard))
        let brighter = try #require(PerceptualHash.dHash(Self.image { x, y in ((x / 8 + y / 8) % 2 == 0) ? 0.15 : 0.95 }))
        #expect(PerceptualHash.hammingDistance(original, brighter) <= 4)
    }

    @Test func differentPicturesAreFarApart() throws {
        let board = try #require(PerceptualHash.dHash(Self.checkerboard))
        let gradient = try #require(PerceptualHash.dHash(Self.rightToLeft))
        #expect(PerceptualHash.hammingDistance(board, gradient) >= 16)
    }

    @Test func hexIsSixteenLowercaseDigits() {
        #expect(PerceptualHash.hex(0) == "0000000000000000")
        #expect(PerceptualHash.hex(0xABC) == "0000000000000abc")
        #expect(PerceptualHash.hex(.max) == "ffffffffffffffff")
    }

    @Test func downscaleCapsTheLongEdgeAt1024() {
        let big = UIImage(cgImage: Self.image(width: 4000, height: 3000) { _, _ in 0.5 })
        let small = PhotoEncoding.downscaled(big)
        #expect(small.size == CGSize(width: 1024, height: 768))
        let tiny = UIImage(cgImage: Self.image(width: 300, height: 200) { _, _ in 0.5 })
        #expect(PhotoEncoding.downscaled(tiny).size == CGSize(width: 300, height: 200)) // never upscaled
        #expect(PhotoEncoding.jpeg(small) != nil)
    }

    @Test func noFaceInAPlainImage() {
        #expect(!FaceCheck.containsFace(Self.checkerboard))
    }
}
