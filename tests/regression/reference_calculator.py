#!/usr/bin/env python3
"""Standalone analytical reference calculator for Impact Lab verification.
Pure standard library. Each function states its assumptions. Run with --selftest.
These are textbook closed forms (agent-reported from memory; self-tests check internal
consistency and known limits, they are not an independent literature check)."""
import math, sys

# ---- Beam bending (Euler-Bernoulli, small strain) ----
FREE_FREE_BL = 4.730040744862704   # first root of cos(bl)cosh(bl)=1
CLAMPED_FREE_BL = 1.875104068711961 # first root for cantilever

def beam_first_frequency(E, rho, L, h, bc="free-free", timoshenko=False, nu=0.0, plane_strain=False):
    """Rectangular beam, unit width. First flexural angular frequency (rad/s).
    Euler-Bernoulli exact. timoshenko=True applies a first-order correction
    1/sqrt(1+(bl)^2 (r/L)^2 (1+E/(kappa G))), kappa=5/6 (approximation, good for L/h>=10)."""
    bl = FREE_FREE_BL if bc == "free-free" else CLAMPED_FREE_BL
    Ep = E / (1 - nu**2) if plane_strain else E
    w = bl**2 * math.sqrt(Ep * h**2 / (12 * rho)) / L**2
    if timoshenko:
        G = E / (2 * (1 + nu))
        w /= math.sqrt(1 + bl**2 * (h**2 / 12) / L**2 * (1 + Ep / (5 / 6 * G)))
    return w

def cantilever_tip_deflection(P, E, L, h, nu=0.0, plane_strain=False, shear=False):
    """Tip load P per unit width: PL^3/(3EI) (+ PL/(kappa G A) if shear=True)."""
    Ep = E / (1 - nu**2) if plane_strain else E
    I = h**3 / 12
    d = P * L**3 / (3 * Ep * I)
    if shear:
        d += P * L / (5 / 6 * E / (2 * (1 + nu)) * h)
    return d

def simply_supported_midspan(P, E, L, h, nu=0.0, plane_strain=False):
    Ep = E / (1 - nu**2) if plane_strain else E
    return P * L**3 / (48 * Ep * h**3 / 12)

# ---- Ring (thin ring, in-plane flexural modes) ----
def ring_frequency(E, rho, R, h, n=2, plane_strain=False, nu=0.0):
    """Thin ring, mean radius R, wall thickness h, unit width, inextensional in-plane modes:
    w_n^2 = n^2 (n^2-1)^2 /(n^2+1) * EI/(rho A R^4). n=2 is the ovalization mode.
    Thick walls (h/R > ~0.1) deviate; treat as approximate."""
    Ep = E / (1 - nu**2) if plane_strain else E
    I, A = h**3 / 12, h
    return math.sqrt(n**2 * (n**2 - 1)**2 / (n**2 + 1) * Ep * I / (rho * A * R**4))

# ---- Hertz line contact (2D, cylinder on plane or cylinder-cylinder), plane strain ----
def hertz_line(F, R1, E1, nu1, R2=math.inf, E2=None, nu2=None):
    """F = load per unit length. Returns (half_width a, peak pressure p0)."""
    E2 = E2 if E2 is not None else E1
    nu2 = nu2 if nu2 is not None else nu1
    Estar = 1 / ((1 - nu1**2) / E1 + (1 - nu2**2) / E2)
    Rstar = 1 / (1 / R1 + (0 if math.isinf(R2) else 1 / R2))
    a = math.sqrt(4 * F * Rstar / (math.pi * Estar))
    return a, 2 * F / (math.pi * a)
# NOTE: 2D Hertz has no finite approach (displacement) without a reference point; compare contact width and peak pressure.

# ---- Sod shock tube (exact Riemann solver, ideal gas) ----
def sod_exact(x, t, left=(1.0, 0.0, 1.0), right=(0.125, 0.0, 0.1), gamma=1.4, x0=0.5):
    """Return (rho, u, p) at x,t. State tuples are (rho,u,p)."""
    rL, uL, pL = left; rR, uR, pR = right
    g = gamma; cL = math.sqrt(g * pL / rL); cR = math.sqrt(g * pR / rR)
    def f(p, r, pk, c):
        if p > pk:
            A = 2 / ((g + 1) * r); B = (g - 1) / (g + 1) * pk
            return (p - pk) * math.sqrt(A / (p + B)), math.sqrt(A / (p + B)) * (1 - (p - pk) / (2 * (p + B)))
        return 2 * c / (g - 1) * ((p / pk) ** ((g - 1) / (2 * g)) - 1), 1 / (r * c) * (p / pk) ** (-(g + 1) / (2 * g))
    p = 0.5 * (pL + pR)
    for _ in range(100):
        fL, dL = f(p, rL, pL, cL); fR, dR = f(p, rR, pR, cR)
        dp = (fL + fR + uR - uL) / (dL + dR); p -= dp
        p = max(p, 1e-12)
        if abs(dp) < 1e-13 * p: break
    us = 0.5 * (uL + uR) + 0.5 * (f(p, rR, pR, cR)[0] - f(p, rL, pL, cL)[0])
    s = (x - x0) / t
    if s <= us:  # left of contact
        if p > pL:
            sh = uL - cL * math.sqrt((g + 1) / (2 * g) * p / pL + (g - 1) / (2 * g))
            if s < sh: return rL, uL, pL
            return rL * ((p / pL + (g - 1) / (g + 1)) / ((g - 1) / (g + 1) * p / pL + 1)), us, p
        shH = uL - cL; cs = cL * (p / pL) ** ((g - 1) / (2 * g)); shT = us - cs
        if s < shH: return rL, uL, pL
        if s > shT: return rL * (p / pL) ** (1 / g), us, p
        u = 2 / (g + 1) * (cL + (g - 1) / 2 * uL + s); c = 2 / (g + 1) * (cL + (g - 1) / 2 * (uL - s))
        return rL * (c / cL) ** (2 / (g - 1)), u, pL * (c / cL) ** (2 * g / (g - 1))
    if p > pR:
        sh = uR + cR * math.sqrt((g + 1) / (2 * g) * p / pR + (g - 1) / (2 * g))
        if s > sh: return rR, uR, pR
        return rR * ((p / pR + (g - 1) / (g + 1)) / ((g - 1) / (g + 1) * p / pR + 1)), us, p
    raise NotImplementedError("right rarefaction not needed for Sod")

# ---- Gas spring (closed adiabatic or isothermal cylinder) ----
def gas_spring_pressure(p0, V0, V, gamma=1.4, isothermal=False):
    return p0 * (V0 / V) ** (1 if isothermal else gamma)

def gas_spring_stiffness(p0, V0, area, gamma=1.4, isothermal=False):
    """Small-oscillation stiffness k = n p0 A^2 / V0 (force per displacement)."""
    return (1 if isothermal else gamma) * p0 * area**2 / V0

def gas_spring_frequency(p0, V0, area, mass, gamma=1.4, isothermal=False):
    return math.sqrt(gas_spring_stiffness(p0, V0, area, gamma, isothermal) / mass)

# ---- 1D thermal conduction ----
def conduction_halfspace(x, t, T0, Ts, alpha):
    """Semi-infinite solid, surface step to Ts: T = Ts + (T0-Ts) erf(x/(2 sqrt(alpha t)))."""
    return Ts + (T0 - Ts) * math.erf(x / (2 * math.sqrt(alpha * t)))

def conduction_slab(x, t, L, Ti, Tw, alpha, terms=200):
    """Slab [0,L], both faces held at Tw, initial uniform Ti (Fourier series)."""
    s = 0.0
    for k in range(terms):
        n = 2 * k + 1
        s += 4 / (math.pi * n) * math.sin(n * math.pi * x / L) * math.exp(-alpha * (n * math.pi / L) ** 2 * t)
    return Tw + (Ti - Tw) * s

def selftest():
    # beam: timoshenko correction lowers frequency, slender limit recovers EB
    w = beam_first_frequency(1e6, 1000, 1, 0.05); wt = beam_first_frequency(1e6, 1000, 1, 0.05, timoshenko=True)
    assert wt < w and abs(wt / w - 1) < 0.02
    assert abs(beam_first_frequency(1e6, 1000, 1, 1e-4, timoshenko=True) / beam_first_frequency(1e6, 1000, 1, 1e-4) - 1) < 1e-6
    # cantilever deflection scales with L^3
    assert abs(cantilever_tip_deflection(1, 1e6, 2, .1) / cantilever_tip_deflection(1, 1e6, 1, .1) - 8) < 1e-12
    # ring n=2: 3? check formula: n^2(n^2-1)^2/(n^2+1) = 4*9/5 = 7.2
    assert abs(ring_frequency(1, 1, 1, math.sqrt(12), 2) ** 2 - 7.2) < 1e-12
    # Hertz: a ~ sqrt(F), p0 ~ sqrt(F)
    a1, p1 = hertz_line(100, .05, 1e9, .3); a2, p2 = hertz_line(400, .05, 1e9, .3)
    assert abs(a2 / a1 - 2) < 1e-12 and abs(p2 / p1 - 2) < 1e-12
    # Sod: star-region pressure and contact speed against standard values
    r, u, p = sod_exact(0.5 + 0.1 * 0.2, 0.2)  # inside star region left of contact
    assert abs(p - 0.30313) < 1e-4 and abs(u - 0.92745) < 1e-4, (r, u, p)
    assert sod_exact(0.0, 0.2)[0] == 1.0 and sod_exact(1.0, 0.2)[0] == 0.125
    # gas spring: stiffness equals -dp/dV derivative numerically
    p0, V0, A = 1e5, 1e-3, 1e-3; dV = 1e-9
    num = -(gas_spring_pressure(p0, V0, V0 + dV) - gas_spring_pressure(p0, V0, V0 - dV)) / (2 * dV) * A * A
    assert abs(num / gas_spring_stiffness(p0, V0, A) - 1) < 1e-6
    # conduction: slab center at long time -> Tw; half-space at x=0 -> Ts
    assert abs(conduction_slab(0.5, 1e6, 1, 100, 0, 1e-3)) < 1e-6
    assert abs(conduction_halfspace(0, 1, 100, 0, 1e-3)) < 1e-12
    # slab and half-space agree at early time near the wall
    assert abs(conduction_slab(0.01, 1.0, 1, 100, 0, 1e-3) - conduction_halfspace(0.01, 1.0, 100, 0, 1e-3)) < 1e-4
    print("reference_calculator self-test: all checks passed")

if __name__ == "__main__":
    if "--selftest" in sys.argv: selftest()
    else:
        w = beam_first_frequency(1e6, 1000, 1, 0.05)
        print("Free-free beam L=1 h=0.05 E=1e6 rho=1000: EB period %.5f s" % (2 * math.pi / w))
        print("Run with --selftest for checks. Import functions for other cases.")
