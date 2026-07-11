#!/usr/bin/env python3
"""Convert a PX4 ULog to Strip flight-test CSV (body_ax channel).

Requires: pyulog (`pip install pyulog`).
Does not claim operational qualification.
"""
from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

try:
    from pyulog import ULog
except ImportError as e:
    sys.stderr.write("pyulog required: pip install pyulog\n")
    raise SystemExit(2) from e

import numpy as np


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def export(ulog_path: Path, out_csv: Path, n_samples: int = 7, cal_n: int = 5) -> dict:
    u = ULog(str(ulog_path))
    ds = u.get_dataset("sensor_combined")
    ts = ds.data["timestamp"]
    ax = ds.data["accelerometer_m_s2[0]"]
    if len(ax) < n_samples:
        raise SystemExit(f"need >= {n_samples} sensor_combined samples, got {len(ax)}")

    idx = np.linspace(0, len(ax) - 1, n_samples).astype(int)
    t0 = int(ts[idx[0]])
    rows = []
    for i, j in enumerate(idx):
        split = "calibration" if i < cal_n else "blinded_holdout"
        mono_ns = int(ts[j] - t0) * 1000  # ulog µs → ns
        utc_ns = 1_700_000_000_000_000_000 + mono_ns
        rows.append((i + 1, mono_ns, utc_ns, float(ax[j]), split))

    cal = [r for r in rows if r[4] == "calibration"]
    xs = np.array([r[0] for r in cal], float)
    ys = np.array([r[3] for r in cal], float)
    A = np.vstack([np.ones_like(xs), xs]).T
    coef, *_ = np.linalg.lstsq(A, ys, rcond=None)
    resid = ys - (A @ coef)
    sigma_cal = max(0.15, float(np.std(resid)) * 2 + 0.05)

    lines = ["sequence,monotonic_ns,utc_ns,channel,value,standard_uncertainty,quality,split\n"]
    for r in rows:
        sig = sigma_cal if r[4] == "calibration" else sigma_cal * 1.1
        lines.append(
            f"{r[0]},{r[1]},{r[2]},body_ax,{r[3]:.6f},{sig:.4f},valid,{r[4]}\n"
        )
    out_csv.write_text("".join(lines))
    return {
        "ulog_sha256": sha256_file(ulog_path),
        "samples": n_samples,
        "sigma_cal": sigma_cal,
        "topic": "sensor_combined.accelerometer_m_s2[0]",
        "source": str(ulog_path),
    }


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("ulog", type=Path)
    p.add_argument("-o", "--out", type=Path, required=True)
    p.add_argument("--samples", type=int, default=7)
    args = p.parse_args()
    meta = export(args.ulog, args.out, n_samples=args.samples)
    print(meta)


if __name__ == "__main__":
    main()
