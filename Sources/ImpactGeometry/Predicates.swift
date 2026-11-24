import Foundation

// Exact geometric predicates on an integer grid.
//
// The mesher snaps every coordinate to integers with |x|, |y| <= 2^24, so
// coordinate differences have at most 25 bits. Under that bound:
//   - orient2d is exact in plain double arithmetic (products < 2^50, sum < 2^51);
//   - incircle is exact using the error-free transformations TwoSum and
//     TwoProduct (via fused multiply-add) and expansion summation, the
//     technique of J. R. Shewchuk, "Adaptive Precision Floating-Point
//     Arithmetic and Fast Robust Geometric Predicates" (1997). This is a fresh,
//     simplified implementation of the published method (no adaptivity is
//     needed because the grid bound makes every intermediate term exact); it
//     does not copy predicates.c, which is in any case public domain.

@inline(__always) func twoSum(_ a: Double, _ b: Double) -> (sum: Double, error: Double) {
    let x = a + b
    let bVirtual = x - a
    let aVirtual = x - bVirtual
    return (x, (a - aVirtual) + (b - bVirtual))
}

@inline(__always) func twoProduct(_ a: Double, _ b: Double) -> (product: Double, error: Double) {
    let p = a * b
    return (p, (-p).addingProduct(a, b))
}

/// Exact sign of a sum of doubles, by Shewchuk's Grow-Expansion.
func exactSign(_ terms: [Double]) -> Int {
    var expansion: [Double] = []
    expansion.reserveCapacity(terms.count * 2)
    for term in terms {
        var q = term
        for i in expansion.indices {
            let (s, e) = twoSum(q, expansion[i])
            expansion[i] = e
            q = s
        }
        expansion.append(q)
    }
    // Components are non-overlapping and increase in magnitude, so the last
    // nonzero component carries the sign of the whole sum.
    for value in expansion.reversed() where value != 0 { return value > 0 ? 1 : -1 }
    return 0
}

/// Twice the signed area of abc. Exact for grid coordinates. Positive when counter-clockwise.
@inline(__always) func orient(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double,
                              _ cx: Double, _ cy: Double) -> Double {
    (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
}

/// Exact sign of the incircle determinant: +1 when d is strictly inside the
/// circle through the counter-clockwise triangle abc, 0 on it, -1 outside.
func inCircleSign(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double,
                  _ cx: Double, _ cy: Double, _ dx: Double, _ dy: Double) -> Int {
    let adx = ax - dx, ady = ay - dy
    let bdx = bx - dx, bdy = by - dy
    let cdx = cx - dx, cdy = cy - dy
    // Each lift and each 2x2 minor is an exact double under the grid bound.
    let alift = adx * adx + ady * ady
    let blift = bdx * bdx + bdy * bdy
    let clift = cdx * cdx + cdy * cdy
    let bc = bdx * cdy - cdx * bdy
    let ca = cdx * ady - adx * cdy
    let ab = adx * bdy - bdx * ady
    let estimate = alift * bc + blift * ca + clift * ab
    let permanent = alift * abs(bc) + blift * abs(ca) + clift * abs(ab)
    // Fast path: a generous bound on the rounding error of the three products and two sums.
    if abs(estimate) > 1e-14 * permanent { return estimate > 0 ? 1 : -1 }
    let t1 = twoProduct(alift, bc), t2 = twoProduct(blift, ca), t3 = twoProduct(clift, ab)
    return exactSign([t1.product, t1.error, t2.product, t2.error, t3.product, t3.error])
}
