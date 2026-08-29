"""Boolean-flatten the mark into one filled path.

A mask-based SVG breaks in two ways that matter: two copies inlined on one page collide on
the mask id, and Android vector drawables have no mask at all. Subtracting the bite and the
letter from the disc up front produces a single path that renders identically everywhere.
"""
import math

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.svgLib.path import parse_path
import pathops

K = 0.5522847498307936  # circle-to-bezier constant


def circle(cx, cy, r):
    p = pathops.Path()
    pen = p.getPen()
    o = r * K
    pen.moveTo((cx + r, cy))
    pen.curveTo((cx + r, cy + o), (cx + o, cy + r), (cx, cy + r))
    pen.curveTo((cx - o, cy + r), (cx - r, cy + o), (cx - r, cy))
    pen.curveTo((cx - r, cy - o), (cx - o, cy - r), (cx, cy - r))
    pen.curveTo((cx + o, cy - r), (cx + r, cy - o), (cx + r, cy))
    pen.closePath()
    return p


def from_d(d, transform=None):
    p = pathops.Path()
    pen = p.getPen()
    parse_path(d, TransformPen(pen, transform) if transform else pen)
    return p


def subtract(base, holes):
    out = pathops.Path()
    pathops.difference([base], list(holes), out.getPen())
    return out


def to_d(path, precision=1):
    pen = SVGPathPen(None, ntos=lambda v: f"{round(v, precision):g}")
    path.draw(pen)
    return pen.getCommands()


def bounds(path):
    return path.bounds
