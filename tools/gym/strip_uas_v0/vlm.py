"""Planar horseshoe vortex-lattice method (VLM) for a trapezoidal wing (``vlm_planar_v0``).

Independent of VSPAERO: a small numpy VLM used for lift slope, span loading and
the wing-alone neutral point. Scope: thin, planar (no dihedral), flat-plate
camber line, small angles, incompressible, linear (no stall, no viscous
effects), trailing legs straight downstream. Geometric twist enters as linear
washout of local incidence from root to tip.

Frame: x aft from the root leading edge, y to starboard, z up; moments about
``x_ref`` are nose-up positive.

Sanity limits checked in tests (not validation against measurements): the
lift slope of rectangular wings tracks the Helmbold estimate, an unswept
rectangular wing has its neutral point at ≈ 25 % chord, and sweeping the wing
back moves the neutral point aft and reduces the lift slope.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any

import numpy as np

from .wing import WingState

LABEL = "vlm_planar_v0"


@dataclass
class Lattice:
    bound_a: np.ndarray  # (N,3) bound-vortex left end
    bound_b: np.ndarray  # (N,3) bound-vortex right end
    cp: np.ndarray  # (N,3) control points
    dy: np.ndarray  # (N,) bound-segment span extent
    twist_rad: np.ndarray  # (N,) local geometric incidence offset
    area: float
    mac: float
    x_le_mac: float


def _x_le(w: WingState, y: np.ndarray | float) -> np.ndarray:
    """Leading-edge x at span station |y| (quarter-chord sweep, root LE at x = 0)."""
    s = 0.5 * w.span_m
    eta = np.abs(np.asarray(y, dtype=float)) / s
    c = w.chord_root_m * (1.0 - (1.0 - w.taper) * eta)
    x_qc = 0.25 * w.chord_root_m + np.abs(y) * math.tan(math.radians(w.sweep_deg))
    return x_qc - 0.25 * c


def _chord(w: WingState, y: np.ndarray | float) -> np.ndarray:
    eta = np.abs(np.asarray(y, dtype=float)) / (0.5 * w.span_m)
    return w.chord_root_m * (1.0 - (1.0 - w.taper) * eta)


def mac_geometry(w: WingState) -> tuple[float, float, float]:
    """(MAC, spanwise station of MAC, x of MAC leading edge) for a trapezoid."""
    lam = w.taper
    y_mac = (w.span_m / 6.0) * (1.0 + 2.0 * lam) / (1.0 + lam)
    return w.mac_m(), y_mac, float(_x_le(w, y_mac))


def build_lattice(w: WingState, n_span: int = 24, n_chord: int = 6, spacing: str = "cosine") -> Lattice:
    s = 0.5 * w.span_m
    th = np.linspace(0.0, math.pi, 2 * n_span + 1)
    ys = -s * np.cos(th) if spacing == "cosine" else np.linspace(-s, s, 2 * n_span + 1)
    a_list, b_list, cp_list, dy_list, tw_list = [], [], [], [], []
    for j in range(len(ys) - 1):
        y0, y1 = ys[j], ys[j + 1]
        ym = 0.5 * (y0 + y1)
        for i in range(n_chord):
            f0, f1 = i / n_chord, (i + 1) / n_chord
            fq = f0 + 0.25 * (f1 - f0)
            fc = f0 + 0.75 * (f1 - f0)
            xa = _x_le(w, y0) + fq * _chord(w, y0)
            xb = _x_le(w, y1) + fq * _chord(w, y1)
            a_list.append((float(xa), y0, 0.0))
            b_list.append((float(xb), y1, 0.0))
            cp_list.append((float(_x_le(w, ym) + fc * _chord(w, ym)), ym, 0.0))
            dy_list.append(y1 - y0)
            tw_list.append(math.radians(w.twist_deg) * abs(ym) / s)
    mac, _, x_le_mac = mac_geometry(w)
    return Lattice(np.array(a_list), np.array(b_list), np.array(cp_list), np.array(dy_list),
                   np.array(tw_list), float(w.area_m2()), float(mac), float(x_le_mac))


def _seg_w(p: np.ndarray, a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """z-velocity at points p (M,3) from unit-strength segments a→b (N,3): (M,N)."""
    r1 = p[:, None, :] - a[None, :, :]
    r2 = p[:, None, :] - b[None, :, :]
    r0 = b - a
    c = np.cross(r1, r2)
    c2 = np.einsum("mnk,mnk->mn", c, c)
    n1 = np.linalg.norm(r1, axis=2)
    n2 = np.linalg.norm(r2, axis=2)
    dot = np.einsum("nk,mnk->mn", r0, r1 / n1[..., None] - r2 / n2[..., None])
    with np.errstate(divide="ignore", invalid="ignore"):
        k = np.where(c2 > 1e-14, dot / c2, 0.0)
    return (c[..., 2] * k) / (4.0 * math.pi)


def _semi_w(p: np.ndarray, a: np.ndarray) -> np.ndarray:
    """z-velocity from unit semi-infinite lines starting at a, running to +x."""
    r = p[:, None, :] - a[None, :, :]
    u = np.array([1.0, 0.0, 0.0])
    c = np.cross(np.broadcast_to(u, r.shape), r)
    c2 = np.einsum("mnk,mnk->mn", c, c)
    nr = np.linalg.norm(r, axis=2)
    with np.errstate(divide="ignore", invalid="ignore"):
        k = np.where(c2 > 1e-14, (1.0 + r[..., 0] / nr) / c2, 0.0)
    return (c[..., 2] * k) / (4.0 * math.pi)


def influence(lat: Lattice) -> np.ndarray:
    p = lat.cp
    return -_semi_w(p, lat.bound_a) + _seg_w(p, lat.bound_a, lat.bound_b) + _semi_w(p, lat.bound_b)


def solve(w: WingState, alpha_deg: float | None = None, *, x_ref: float | None = None,
          n_span: int = 24, n_chord: int = 6) -> dict[str, Any]:
    """CL, CM (about ``x_ref``; default quarter-MAC), CL_alpha, neutral point, span loading."""
    lat = build_lattice(w, n_span, n_chord)
    A = influence(lat)
    alpha = math.radians(w.alpha_deg if alpha_deg is None else alpha_deg)
    xr = (lat.x_le_mac + 0.25 * lat.mac) if x_ref is None else float(x_ref)
    xb = 0.5 * (lat.bound_a[:, 0] + lat.bound_b[:, 0])

    def coeffs(rhs: np.ndarray) -> tuple[float, float, np.ndarray]:
        g = np.linalg.solve(A, rhs)
        lift = 2.0 * float(np.sum(g * lat.dy)) / lat.area
        cm = -2.0 * float(np.sum(g * lat.dy * (xb - xr))) / (lat.area * lat.mac)
        return lift, cm, g

    cl, cm, g = coeffs(-(alpha + lat.twist_rad))
    cla, cma, _ = coeffs(-np.ones_like(lat.twist_rad))  # per radian, no twist
    x_np = xr - lat.mac * cma / cla
    return {
        "label": LABEL, "CL": cl, "CM": cm, "x_ref_m": xr, "CL_alpha_per_rad": cla,
        "CM_alpha_per_rad": cma, "x_np_m": x_np, "mac_m": lat.mac, "x_le_mac_m": lat.x_le_mac,
        "np_frac_mac": (x_np - lat.x_le_mac) / lat.mac, "area_m2": lat.area,
        "n_panels": int(len(lat.dy)), "alpha_deg": math.degrees(alpha),
        "notes": "Planar flat-plate VLM: linear, inviscid, no stall/camber/dihedral. Ranking/stability proxy.",
    }


def helmbold_cla(ar: float) -> float:
    """Helmbold low-AR / lifting-line blend for an unswept wing [1/rad] (comparison only)."""
    return 2.0 * math.pi * ar / (2.0 + math.sqrt(ar * ar + 4.0))
