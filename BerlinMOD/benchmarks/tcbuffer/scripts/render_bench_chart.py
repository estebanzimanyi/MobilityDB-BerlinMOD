#!/usr/bin/env python3
"""Render the tcbuffer vs tgeompoint timing matrix as a grouped bar SVG.

Mirrors MobilityDB-BerlinMOD's cross-platform chart style: a single
SVG with one bar per (operator, model) pair, log-scaled Y axis, no
external data files (all numbers live as literals below so the chart
is reproducible from one source of truth).

Output: ``tcbuffer_vs_tgeompoint.svg`` next to the bench doc.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


@dataclass(frozen=True)
class Series:
    label: str
    color: str
    # operator label -> seconds; values that are None render as a flat
    # marker at the y-axis floor labelled "n/a".
    timings: dict[str, float | None]


# Operator -> (Trip seconds, Noise seconds). Numbers from
# tcbuffer_timings_2026-05-14.md (run dated 2026-05-15). Every
# operator in the catalog is registered and measured on both sides.
OPERATORS: list[tuple[str, float, float]] = [
    # Section A1 — restrict
    ("atGeometry",          2.61,    3.55),
    ("minusGeometry",       3.41,    5.72),
    ("atStbox",             2.53,    4.58),
    ("minusStbox",          2.61,    6.43),
    # Section A2 — distance to a geometry
    ("|=|",                56.79,  109.29),
    ("nearestApproachInst", 342.70, 364.58),
    ("shortestLine",       53.03,  127.47),
    ("centroid <->",       28.57,   25.77),
    # Section A3 — ever/always vs geometry
    ("eContains",           7.29,   16.52),
    ("aContains",           6.64,    2.80),
    ("eCovers",             6.69,   16.30),
    ("aCovers",             8.67,    2.61),
    ("eDisjoint",           4.08,    3.16),
    ("aDisjoint",           9.02,   14.90),
    ("eDwithin",           73.86,   26.60),
    ("aDwithin",           21.18,    2.79),
    ("eIntersects",         6.00,    3.21),
    ("aIntersects",         8.66,   14.79),
    ("eTouches",            3.55,   49.48),
    ("aTouches",            3.94,   49.24),
    # Section A4 — temporal-output vs geometry
    ("tIntersects",         3.92,  258.15),
    ("tDisjoint",           2.62,  201.76),
    ("tContains",           3.15,    7.59),
    ("tCovers",             3.42,    6.71),
    ("tDwithin",           17.73,  347.64),
    ("tTouches",            2.64,    7.10),
    # Section C5 — set-to-set min distance aggregate
    ("minDistance set×set", 51.10,  62.90),
]


def render(out: Path) -> None:
    labels = [op for op, _, _ in OPERATORS]
    trip = [t for _, t, _ in OPERATORS]
    noise = [n for _, _, n in OPERATORS]
    n = len(labels)
    width = 0.4
    x = np.arange(n)
    floor = 0.05  # 50 ms floor

    fig, ax = plt.subplots(figsize=(max(10, n * 0.55), 5.2), dpi=120)

    ax.bar(x - width / 2, trip, width=width * 0.95,
           color="#1f77b4", label="Trip (tgeompoint)", edgecolor="white",
           linewidth=0.4)
    ax.bar(x + width / 2, noise, width=width * 0.95,
           color="#ff7f0e", label="Noise (tcbuffer)", edgecolor="white",
           linewidth=0.4)

    # Annotate the slow Noise bars so the reader sees the headline costs.
    for xi, v in zip(x + width / 2, noise):
        if v >= 100.0:
            ax.text(xi, v * 1.07, f"{v:.0f}s", ha="center", va="bottom",
                    fontsize=7, color="#333333", rotation=0)

    ax.set_yscale("log")
    top = max(max(trip), max(noise)) * 2.0
    ax.set_ylim(floor, top)
    ax.set_xticks(x)
    ax.set_xticklabels(labels, rotation=60, ha="right", fontsize=8)
    ax.set_ylabel("Wall-clock seconds, log scale (cross-join)")
    ax.set_title(
        "tcbuffer vs tgeompoint on AIS, 2026-05-15\n"
        "100 vessels x 100 protected natural areas, MobilityDB 1.4 on PG 17"
    )
    ax.grid(True, which="both", axis="y", alpha=0.3)
    ax.legend(loc="upper left", fontsize=9)

    # Section separators between A1 / A2 / A3 / A4 / C5 boundaries.
    for boundary in (3.5, 7.5, 19.5, 25.5):
        ax.axvline(boundary, color="#888888", linewidth=0.6, alpha=0.5)
    section_labels = [
        (1.5,  "A1 restrict"),
        (5.5,  "A2 distance"),
        (13.5, "A3 e/a-rels"),
        (22.5, "A4 t-rels"),
        (26.0, "C5 minDist"),
    ]
    ymin_data = ax.get_ylim()[0]
    for xi, label in section_labels:
        ax.text(xi, ymin_data * 1.15, label, ha="center", va="bottom",
                fontsize=8, color="#444444", style="italic")

    fig.tight_layout()
    fig.savefig(out, format="svg")
    plt.close(fig)
    print(f"wrote {out}")


def main() -> int:
    out = Path(__file__).parent.parent / "tcbuffer_vs_tgeompoint.svg"
    render(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
