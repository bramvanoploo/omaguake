#!/usr/bin/env python3
"""Crop a change-isolated region out of a pair of full-screen screenshots.

Usage: crop_diff.py BEFORE AFTER OUT [--threshold N] [--min-rows N]

Taking one screenshot with the OmaGuake surface closed and one with it open
makes the surface the only difference between the frames, so its bounds are
found by differencing rather than by keying on theme colors or by predicting
geometry from a scale factor. Both frames must be the same size (same monitor,
same scale), and nothing else on screen may change between them.

Bar regions are excluded (the clock ticks), and the changed rows/columns are
taken as their longest contiguous runs, so stray cursor or tooltip noise
outside the card does not stretch the crop.
"""
import argparse
import subprocess
import sys

from PIL import Image, ImageChops


def work_area_top():
    """Device-pixel y of the top of the work area (below the reserved bar)."""
    try:
        mon = subprocess.run(["hyprctl", "monitors", "-j"],
                             capture_output=True, text=True)
        first = __import__("json").loads(mon.stdout)[0]
        scale = first.get("scale", 1) or 1
        return round(max(0, first["reserved"][1]) * scale)
    except Exception:
        return 0  # no hyprctl / not on Hyprland: search the whole frame


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("before")
    ap.add_argument("after")
    ap.add_argument("out")
    ap.add_argument("--threshold", type=int, default=12,
                    help="min per-pixel max-channel delta to count as a change")
    ap.add_argument("--min-rows", type=int, default=40,
                    help="smallest plausible card height, in pixels")
    args = ap.parse_args()

    before = Image.open(args.before).convert("RGB")
    after = Image.open(args.after).convert("RGB")
    if before.size != after.size:
        sys.exit(f"frames differ in size ({before.size} vs {after.size}); "
                 "both screenshots must come from the same monitor and scale")
    W, H = after.size

    diff = ImageChops.difference(before, after)
    # Max across channels, not luminance: the card background sits close to a
    # dark desktop in brightness (delta ~15 in L) while differing clearly in
    # each channel, and a luminance mask would then see only the card's text
    # and accents as changed - no solid block to crop.
    r, g, b = diff.split()
    dmax = ImageChops.lighter(ImageChops.lighter(r, g), b)
    mask = dmax.point(lambda v: 255 if v >= args.threshold else 0)
    px = mask.load()
    top = min(work_area_top(), H - 1)

    row_hits = [0] * H
    col_hits = [0] * W
    for y in range(top, H):
        for x in range(W):
            if px[x, y]:
                row_hits[y] += 1
                col_hits[x] += 1

    def longest_run(hits, limit, n_total):
        """Longest contiguous run of rows/cols above `limit` changes."""
        best = (0, 0)
        start = None
        for i, n in enumerate(hits):
            if n > limit:
                if start is None:
                    start = i
            elif start is not None:
                if i - start > best[1] - best[0]:
                    best = (start, i)
                start = None
        if start is not None and n_total - start > best[1] - best[0]:
            best = (start, n_total)
        return best

    peak = max(row_hits) or 1
    y0, y1 = longest_run(row_hits, max(8, peak * 0.35), H)
    peak_x = max(col_hits) or 1
    x0, x1 = longest_run(col_hits, max(8, peak_x * 0.35), W)

    if y1 - y0 < args.min_rows or x1 - x0 < 40:
        sys.exit(
            f"no card-shaped change found between {args.before} and {args.after} "
            f"(box {x1 - x0}x{y1 - y0}). Is the surface actually visible in "
            f"{args.after}, identical in {args.before}, and is the threshold "
            f"(--threshold {args.threshold}) right for this theme?")

    after.crop((x0, y0, x1, y1)).save(args.out)
    print(f"cropped {x1 - x0}x{y1 - y0} at ({x0},{y0}) -> {args.out}")


if __name__ == "__main__":
    main()
