#!/usr/bin/env python3
"""Fetch public aero reference data for Strip into data/cache/ (git-ignored), sha256-checked.

UIUC LSAT airfoil data are distributed under the GNU GPL (coordinates are
explicitly *not* covered by it). Strip is Apache-2.0, so the files are fetched at
use time rather than committed; only derived validation statistics are committed.

    python data/fetch/fetch_strip_data.py            # LSAT volumes 1-3
"""

from __future__ import annotations

import argparse
import hashlib
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / "cache"

SOURCES = {
    "uiuc_lsat_vol1": ("https://m-selig.ae.illinois.edu/pd/pub/lsat/volume01.zip",
                       "124b990a3d22163cadf6efb8e805860e89275f2f987d96e4fbe7a07bda8e03ab"),
    "uiuc_lsat_vol2": ("https://m-selig.ae.illinois.edu/pd/pub/lsat/volume02.zip",
                       "5a678fd02ed71ffd4a0a2c4a9f891f739001426ab0d258f7d7370389f0b121c3"),
    "uiuc_lsat_vol3": ("https://m-selig.ae.illinois.edu/pd/pub/lsat/volume03.zip",
                       "199e7fd9441469c4c49ab21b4f3443cd0de26d950a7053cf6d0e53575b706421"),
}


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def fetch(key: str, *, force: bool = False) -> Path:
    url, want = SOURCES[key]
    CACHE.mkdir(parents=True, exist_ok=True)
    dest = CACHE / f"{key}.zip"
    if force or not dest.exists():
        req = urllib.request.Request(url, headers={"User-Agent": "strip-data-fetch/1"})
        with urllib.request.urlopen(req, timeout=120) as r:
            dest.write_bytes(r.read())
    got = sha256(dest)
    if want and got != want:
        raise SystemExit(f"{key}: sha256 mismatch {got} != {want}")
    with zipfile.ZipFile(dest) as z:
        z.extractall(CACHE / "uiuc_lsat")
    return dest


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", action="append")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    for k in a.only or SOURCES:
        print("ok", k, fetch(k, force=a.force).relative_to(ROOT.parent))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
