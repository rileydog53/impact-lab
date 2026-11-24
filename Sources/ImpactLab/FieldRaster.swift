import CoreGraphics
import ImpactPhysics
import SwiftUI

/// Draws a recovered scalar field as a continuous image. The scalar is interpolated across each
/// triangle and colour-mapped per pixel, so no triangle edges show unless the mesh overlay is on.
/// Display only: the input is solver output after averaging, see SmoothField.swift.
enum FieldRaster {
    struct Output {
        let image: CGImage
        /// Screen rectangle the image covers.
        let rect: CGRect
    }

    static func render(screen nodes: [CGPoint], triangles: [SIMD3<Int>], corners: [SIMD3<Double>],
                       limit: Double, signed: Bool, scale: CGFloat) -> Output? {
        guard !triangles.isEmpty, scale > 0 else { return nil }
        var minX = CGFloat.infinity, minY = CGFloat.infinity, maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for t in triangles { for n in [t.x, t.y, t.z] {
            minX = min(minX, nodes[n].x); maxX = max(maxX, nodes[n].x)
            minY = min(minY, nodes[n].y); maxY = max(maxY, nodes[n].y)
        } }
        let rect = CGRect(x: floor(minX), y: floor(minY), width: ceil(maxX - floor(minX)) + 1, height: ceil(maxY - floor(minY)) + 1)
        let width = Int(rect.width * scale), height = Int(rect.height * scale)
        guard width > 0, height > 0, width * height < 36_000_000 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let map: FieldColormap = signed ? .diverging : .sequential
        // 256-entry lookup keeps the pixel loop cheap.
        let lut: [(UInt8, UInt8, UInt8)] = (0..<256).map { i in
            let c = map.color(Double(i) / 255)
            return (UInt8(c.x * 255 + 0.5), UInt8(c.y * 255 + 0.5), UInt8(c.z * 255 + 0.5))
        }
        let eps = -0.002   // slight overdraw so neighbouring triangles leave no seams
        for (ti, t) in triangles.enumerated() {
            let p0 = nodes[t.x], p1 = nodes[t.y], p2 = nodes[t.z]
            let ax = Double((p0.x - rect.minX) * scale), ay = Double((p0.y - rect.minY) * scale)
            let bx = Double((p1.x - rect.minX) * scale), by = Double((p1.y - rect.minY) * scale)
            let cx = Double((p2.x - rect.minX) * scale), cy = Double((p2.y - rect.minY) * scale)
            let det = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            guard abs(det) > 1e-12 else { continue }
            let x0 = max(0, Int(floor(min(ax, bx, cx)))), x1 = min(width - 1, Int(ceil(max(ax, bx, cx))))
            let y0 = max(0, Int(floor(min(ay, by, cy)))), y1 = min(height - 1, Int(ceil(max(ay, by, cy))))
            guard x0 <= x1, y0 <= y1 else { continue }
            let v = corners[ti]
            let lo = signed ? -limit : 0
            for y in y0...y1 {
                let py = Double(y) + 0.5
                for x in x0...x1 {
                    let px = Double(x) + 0.5
                    let l0 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / det
                    let l1 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / det
                    let l2 = 1 - l0 - l1
                    guard l0 >= eps, l1 >= eps, l2 >= eps else { continue }
                    let value = l0 * v.x + l1 * v.y + l2 * v.z
                    let u = limit > 0 ? (value - lo) / (signed ? 2 * limit : limit) : 0
                    let c = lut[Int(min(1, max(0, u.isNaN ? 0 : u)) * 255 + 0.5)]
                    let o = (y * width + x) * 4
                    pixels[o] = c.0; pixels[o + 1] = c.1; pixels[o + 2] = c.2; pixels[o + 3] = 255
                }
            }
        }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true,
                                  intent: .defaultIntent) else { return nil }
        return Output(image: image, rect: rect)
    }
}

/// Continuous colour bar with ticks and units, for the smooth display.
struct SmoothFieldLegend: View {
    let field: AssemblyField
    let limit: Double

    var body: some View {
        let map: FieldColormap = field.signed ? .diverging : .sequential
        let stops = (0...16).map { i -> Color in
            let c = map.color(Double(i) / 16)
            return Color(red: c.x, green: c.y, blue: c.z)
        }
        let low = field.signed ? -limit : 0
        HStack(spacing: 6) {
            Text(field.display(low, limit: limit))
            VStack(spacing: 1) {
                LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing)
                    .frame(width: 120, height: 8).clipShape(.capsule)
                if field.signed {
                    Text("0").font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
            Text(field.display(limit, limit: limit))
        }
        .font(.caption.monospacedDigit())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Smooth color scale \(field.display(low, limit: limit)) to \(field.display(limit, limit: limit))")
        .help("Interpolated display of solver output (area-weighted averaging). Values beyond the scale use the end colors.")
    }
}
