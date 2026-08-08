"""Minimal SVG path reader — enough to measure a Phosphor glyph's ink box.

Phosphor's `core` SVGs are the narrowest possible dialect: a single
`viewBox="0 0 256 256"`, one or two `<path>` elements, one `d` attribute each,
no strokes, no transforms, no groups. So this only has to flatten a path into
points accurately enough to bound it — it is a measuring tape, not a renderer.

Supported commands: M L H V C S Q T A Z (absolute and relative).
"""

from __future__ import annotations

import math
import re

_TOKEN = re.compile(r"[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?")

# Curves are sampled rather than solved. 24 samples per segment bounds a
# 256-unit glyph to well under a tenth of a unit, which is two orders of
# magnitude finer than anything the symbol geometry cares about.
_SAMPLES = 24


def _tokenize(d: str) -> list:
    out = []
    for raw in _TOKEN.findall(d):
        out.append(raw if raw.isalpha() else float(raw))
    return out


def _cubic(p0, p1, p2, p3, t):
    u = 1.0 - t
    return (
        u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0],
        u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1],
    )


def _quad(p0, p1, p2, t):
    u = 1.0 - t
    return (
        u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
        u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1],
    )


def _arc_points(p0, rx, ry, phi_deg, large_arc, sweep, p1):
    """SVG endpoint-parameterised arc → sampled points (F.6.5 of the spec)."""
    if rx == 0 or ry == 0 or p0 == p1:
        return [p1]
    phi = math.radians(phi_deg)
    cos_p, sin_p = math.cos(phi), math.sin(phi)
    dx2, dy2 = (p0[0] - p1[0]) / 2.0, (p0[1] - p1[1]) / 2.0
    x1p = cos_p * dx2 + sin_p * dy2
    y1p = -sin_p * dx2 + cos_p * dy2
    rx, ry = abs(rx), abs(ry)
    lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lam > 1:
        scale = math.sqrt(lam)
        rx, ry = rx * scale, ry * scale
    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    coef = math.sqrt(max(num / den, 0.0))
    if large_arc == sweep:
        coef = -coef
    cxp = coef * rx * y1p / ry
    cyp = -coef * ry * x1p / rx
    cx = cos_p * cxp - sin_p * cyp + (p0[0] + p1[0]) / 2.0
    cy = sin_p * cxp + cos_p * cyp + (p0[1] + p1[1]) / 2.0

    def angle(ux, uy, vx, vy):
        dot = ux * vx + uy * vy
        norm = math.hypot(ux, uy) * math.hypot(vx, vy)
        a = math.acos(max(-1.0, min(1.0, dot / norm))) if norm else 0.0
        return -a if ux * vy - uy * vx < 0 else a

    theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not sweep and delta > 0:
        delta -= 2 * math.pi
    elif sweep and delta < 0:
        delta += 2 * math.pi

    pts = []
    for i in range(1, _SAMPLES + 1):
        th = theta1 + delta * i / _SAMPLES
        pts.append((
            cos_p * rx * math.cos(th) - sin_p * ry * math.sin(th) + cx,
            sin_p * rx * math.cos(th) + cos_p * ry * math.sin(th) + cy,
        ))
    return pts


def path_points(d: str) -> list:
    """Every on-curve and sampled point of a path, in user units."""
    tokens = _tokenize(d)
    pts: list = []
    cur = (0.0, 0.0)
    start = (0.0, 0.0)
    prev_cubic_ctrl = None
    prev_quad_ctrl = None
    cmd = None
    i = 0
    while i < len(tokens):
        if isinstance(tokens[i], str):
            cmd = tokens[i]
            i += 1
            if cmd in "Zz":
                cur = start
                pts.append(cur)
                prev_cubic_ctrl = prev_quad_ctrl = None
                continue
        elif cmd is None:
            break
        eff = cmd
        rel = eff.islower()
        up = eff.upper()

        def take(n):
            nonlocal i
            vals = tokens[i:i + n]
            i += n
            return vals

        if up == "M":
            x, y = take(2)
            cur = (cur[0] + x, cur[1] + y) if rel else (x, y)
            start = cur
            pts.append(cur)
            prev_cubic_ctrl = prev_quad_ctrl = None
            cmd = "l" if rel else "L"
        elif up == "L":
            x, y = take(2)
            cur = (cur[0] + x, cur[1] + y) if rel else (x, y)
            pts.append(cur)
            prev_cubic_ctrl = prev_quad_ctrl = None
        elif up == "H":
            (x,) = take(1)
            cur = (cur[0] + x, cur[1]) if rel else (x, cur[1])
            pts.append(cur)
            prev_cubic_ctrl = prev_quad_ctrl = None
        elif up == "V":
            (y,) = take(1)
            cur = (cur[0], cur[1] + y) if rel else (cur[0], y)
            pts.append(cur)
            prev_cubic_ctrl = prev_quad_ctrl = None
        elif up in ("C", "S"):
            if up == "C":
                x1, y1, x2, y2, x, y = take(6)
                c1 = (cur[0] + x1, cur[1] + y1) if rel else (x1, y1)
            else:
                x2, y2, x, y = take(4)
                c1 = (2 * cur[0] - prev_cubic_ctrl[0], 2 * cur[1] - prev_cubic_ctrl[1]) if prev_cubic_ctrl else cur
            c2 = (cur[0] + x2, cur[1] + y2) if rel else (x2, y2)
            end = (cur[0] + x, cur[1] + y) if rel else (x, y)
            for s in range(1, _SAMPLES + 1):
                pts.append(_cubic(cur, c1, c2, end, s / _SAMPLES))
            cur, prev_cubic_ctrl, prev_quad_ctrl = end, c2, None
        elif up in ("Q", "T"):
            if up == "Q":
                x1, y1, x, y = take(4)
                c1 = (cur[0] + x1, cur[1] + y1) if rel else (x1, y1)
            else:
                x, y = take(2)
                c1 = (2 * cur[0] - prev_quad_ctrl[0], 2 * cur[1] - prev_quad_ctrl[1]) if prev_quad_ctrl else cur
            end = (cur[0] + x, cur[1] + y) if rel else (x, y)
            for s in range(1, _SAMPLES + 1):
                pts.append(_quad(cur, c1, end, s / _SAMPLES))
            cur, prev_quad_ctrl, prev_cubic_ctrl = end, c1, None
        elif up == "A":
            rx, ry, rot, large, sweep, x, y = take(7)
            end = (cur[0] + x, cur[1] + y) if rel else (x, y)
            pts.extend(_arc_points(cur, rx, ry, rot, int(large), int(sweep), end))
            cur, prev_cubic_ctrl, prev_quad_ctrl = end, None, None
        else:
            raise ValueError(f"unsupported path command {eff!r}")
    return pts


def bbox(paths: list) -> tuple:
    """(min_x, min_y, max_x, max_y) over a list of `d` strings."""
    xs, ys = [], []
    for d in paths:
        for x, y in path_points(d):
            xs.append(x)
            ys.append(y)
    if not xs:
        raise ValueError("empty path")
    return min(xs), min(ys), max(xs), max(ys)
