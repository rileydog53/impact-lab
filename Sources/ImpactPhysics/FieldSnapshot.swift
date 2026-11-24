#if canImport(CoreGraphics) && canImport(ImageIO) && canImport(CoreText)
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// PNG of one frame in the smooth view for reports: bodies with the continuous colour map, a colour bar with
/// units, and an honest caption. Display of solver output, not a new calculation.
public enum FieldSnapshot {
    public struct Layer { public var positions: [Point]; public var triangles: [SIMD3<Int>]; public var corners: [SIMD3<Double>]
        public init(positions: [Point], triangles: [SIMD3<Int>], corners: [SIMD3<Double>]) {
            self.positions = positions; self.triangles = triangles; self.corners = corners } }

    public static func png(layers: [Layer], limit: Double, signed: Bool, title: String, unit: String, unitScale: Double,
                           width: Int = 1200) -> Data? {
        var all: [Point] = []
        for l in layers { all += l.positions }
        guard let first = all.first else { return nil }
        var lo = first, hi = first
        for p in all { lo = Point(min(lo.x, p.x), min(lo.y, p.y)); hi = Point(max(hi.x, p.x), max(hi.y, p.y)) }
        let margin = 40.0, header = 56.0, footer = 70.0
        let scale = (Double(width) - 2 * margin) / max(1e-12, hi.x - lo.x)
        let bodyH = (hi.y - lo.y) * scale
        let height = Int(bodyH + header + footer + 2 * margin)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        func text(_ s: String, x: Double, y: Double, size: CGFloat = 20) {
            let attrs = [kCTFontAttributeName: CTFontCreateWithName("Helvetica" as CFString, size, nil),
                         kCTForegroundColorFromContextAttributeName: true] as CFDictionary
            let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, s as CFString, attrs))
            ctx.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
            ctx.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(line, ctx)
        }
        text(title, x: margin, y: Double(height) - margin - 8, size: 24)
        let top = Double(height) - margin - header
        for l in layers {
            let screen = l.positions.map { CGPoint(x: ($0.x - lo.x) * scale, y: (hi.y - $0.y) * scale) }
            if let out = FieldRaster.render(screen: screen, triangles: l.triangles, corners: l.corners,
                                            limit: limit, signed: signed, scale: 1) {
                ctx.draw(out.image, in: CGRect(x: margin + out.rect.minX, y: top - out.rect.maxY,
                                               width: out.rect.width, height: out.rect.height))
            }
        }
        // Colour bar.
        let map: FieldColormap = signed ? .diverging : .sequential
        let barY = margin + 26, barW = 420.0
        for i in 0..<Int(barW) {
            let c = map.color(Double(i) / (barW - 1))
            ctx.setFillColor(CGColor(red: c.x, green: c.y, blue: c.z, alpha: 1))
            ctx.fill(CGRect(x: margin + Double(i), y: barY, width: 1, height: 14))
        }
        func label(_ v: Double) -> String { String(format: "%.3g %@", v * unitScale, unit) }
        text(label(signed ? -limit : 0), x: margin, y: barY - 22, size: 16)
        text(label(limit), x: margin + barW - 70, y: barY - 22, size: 16)
        if signed { text("0", x: margin + barW / 2 - 4, y: barY - 22, size: 16) }
        text("Interpolated display of solver output (area-weighted nodal averaging); peaks may read lower than raw element values.",
             x: margin, y: margin - 18, size: 13)
        guard let image = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// Von Mises stress snapshot of a replay frame (or any frame field via `value`).
    public static func png(frame: AssemblyReplayFrame, title: String, unit: String, unitScale: Double, signed: Bool,
                           limit: Double? = nil, value: (AssemblyReplayBody) -> [Double]) -> Data? {
        var layers: [Layer] = []
        var peak = 0.0
        for b in frame.bodies {
            let v = value(b)
            guard v.count == b.body.mesh.elements.count else { continue }
            peak = max(peak, v.map(abs).max() ?? 0)
            let field = b.body.scalarField(elementValues: v)
            layers.append(Layer(positions: b.body.position, triangles: field.triangles, corners: field.recoveredCorners()))
        }
        return png(layers: layers, limit: limit ?? max(peak, 1e-30), signed: signed, title: title, unit: unit, unitScale: unitScale)
    }
}
#endif
