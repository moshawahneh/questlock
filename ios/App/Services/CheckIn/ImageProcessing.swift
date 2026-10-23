import CoreGraphics
import UIKit

/// 64-bit difference hash ("dHash"). Unlike SHA-256, similar-looking photos get similar hashes,
/// so the server can catch the same photo being reused (small Hamming distance) even after re-encoding.
enum PerceptualHash {
    /// Averages the image into 9×8 grey cells and sets one bit per neighbouring pair: 1 if the left cell
    /// is brighter than the one to its right. 8 rows × 8 comparisons = 64 bits.
    ///
    /// The averaging is done here rather than by letting CoreGraphics draw straight into a 9×8 bitmap:
    /// its high-quality downscaler corrupts the last few pixels of the bottom row at tiny sizes.
    static func dHash(_ image: CGImage) -> UInt64? {
        // 1. Grey pixels, at most 1024 px on the long side (check-in photos already are).
        let scale = min(1, 1024 / Double(max(image.width, image.height)))
        let width = max(9, Int((Double(image.width) * scale).rounded()))
        let height = max(8, Int((Double(image.height) * scale).rounded()))
        var grey = [UInt8](repeating: 0, count: width * height)
        let drawn = grey.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        // 2. Mean brightness of each of the 9×8 cells.
        var cells = [Double](repeating: 0, count: 9 * 8)
        for cy in 0..<8 {
            let y0 = cy * height / 8, y1 = (cy + 1) * height / 8
            for cx in 0..<9 {
                let x0 = cx * width / 9, x1 = (cx + 1) * width / 9
                var sum = 0
                for y in y0..<y1 {
                    for x in x0..<x1 { sum += Int(grey[y * width + x]) }
                }
                cells[cy * 9 + cx] = Double(sum) / Double((y1 - y0) * (x1 - x0))
            }
        }

        // 3. Compare neighbours.
        var hash: UInt64 = 0
        for cy in 0..<8 {
            for cx in 0..<8 {
                hash <<= 1
                if cells[cy * 9 + cx] > cells[cy * 9 + cx + 1] {
                    hash |= 1
                }
            }
        }
        return hash
    }

    /// Number of differing bits: 0 = same picture, ~32 = unrelated, 64 = exact opposite.
    static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    /// 16 lowercase hex digits, the format verify-checkin expects.
    static func hex(_ hash: UInt64) -> String {
        String(format: "%016llx", hash)
    }
}

enum PhotoEncoding {
    /// Draws the photo upright (applying its orientation) at most `maxLongEdge` pixels on the long side.
    static func downscaled(_ image: UIImage, maxLongEdge: CGFloat = 1024) -> UIImage {
        let longEdge = max(image.size.width, image.size.height)
        let scale = min(1, maxLongEdge / longEdge)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    static func jpeg(_ image: UIImage, quality: CGFloat = 0.7) -> Data? {
        image.jpegData(compressionQuality: quality)
    }
}
