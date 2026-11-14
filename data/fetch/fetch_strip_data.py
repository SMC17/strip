#!/usr/bin/env python3
"""Fetch public aero reference data for Strip into data/cache/ (git-ignored), sha256-checked.

UIUC LSAT airfoil data are distributed under the GNU GPL (coordinates are
explicitly *not* covered by it). Strip is Apache-2.0, so the files are fetched at
use time rather than committed; only derived validation statistics are committed.

    python data/fetch/fetch_strip_data.py            # LSAT volumes 1-6 + UIUC ADS coordinates

LSAT volumes 4-6 ship no coordinate files; their airfoils are matched to nominal
coordinates from the UIUC Airfoil Coordinates Database (``ADS_COORDS``; licence not stated on
the page, treated as GPL-like: fetched, never committed). Volumes 1-3 use the measured
wind-tunnel-model coordinates they ship.
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
    "uiuc_lsat_vol4": ("https://m-selig.ae.illinois.edu/pd/pub/lsat/volume04.zip",
                       "4b9db14ba466ef96d80c90cfa77ab97f9d0ea48ecd7c449b2772e92076a54a94"),
    "uiuc_lsat_vol5": ("https://m-selig.ae.illinois.edu/pd/pub/lsat/volume05.zip",
                       "35e15b8e89c0b32cc148867df9926403fcf5a64ceadcfe114f072a05fc25c190"),
    "uiuc_lsat_vol6": ("https://m-selig.ae.illinois.edu/pd/pub/lsat/volume06.zip",
                       "987d4b6a412e7c7fd0b186891e131c1b8aa5a0bb39a677ad76827c630d9b3186"),
}

ADS_URL = "https://m-selig.ae.illinois.edu/ads/coord/{}.dat"
ADS_COORDS = {
    "e387": "98aa8a4076edbfd1c52e3a2d0cf17b1ef1cbc51ae5da3ab8e5361047b89ee523",
    "fx63137": "8c3a70fa1639885a72bb1394ff6666db637efc4971d3594f1a3882c1b9f18c5d",
    "sd2030": "97d21c5c7b5a67394fe8b84a11e00e9a1b03e8dbe0dcf511c08b09832625c944",
    "ag12": "e0293564f3f15d44618476dbd95c6f44dba9719bf7d8964b63158d64c633676d",
    "ag16": "c79b3de499aee67501086d2e51fbd742b0d8c25c7b84e06ae70548813bc03b61",
    "ag24": "1552656c71d7141857be1af1cef11fec749a380708bd95d24ee18fe7b872a731",
    "ag35": "60a9404d4ee627329804e7a78038e9055ab2070ba436a3dcb5b90ac2b4b40fb7",
    "cal1215j": "3732fc17067778eb64bffd211ec4cfaa33b1bde818c27bd8a48c2667010edd7d",
    "cal2263m": "f192394260eb5633e5e9c66975925901484606753a5ff1860ac0066b19a5d1d8",
    "cal4014l": "4eec8fe6f6388c5cc0588b922bc77b64546b7dfc3b8d2c7902afd95840d0258d",
    "ma409": "9c508c0b4c57832fbddd8d45e6f5b10f31d091c077018f18fb68ad3ded12927e",
    "s8064": "399734744affb0ca626d76d54f697d60a55ae355bce98cde3e57019b03405051",
    "s9000": "ec6984c9f76e5ca906ea261c6f89ef0c885582e36554085bcf61a223b94f6c8f",
    "w1011": "ce82f925f88b695c1f2467db0ede51ec3f71d35443bf4056ed460a0f202a3eb5",
    "w1015": "140922b7f6789324d99fed55cd135401f6e4eae5bd8dca95de1cdb1861d5fc73",
}


def fetch_coords(*, force: bool = False) -> Path:
    d = CACHE / "uiuc_ads"
    d.mkdir(parents=True, exist_ok=True)
    for name, want in ADS_COORDS.items():
        dest = d / f"{name}.dat"
        if force or not dest.exists():
            req = urllib.request.Request(ADS_URL.format(name), headers={"User-Agent": "strip-data-fetch/1"})
            with urllib.request.urlopen(req, timeout=60) as r:
                dest.write_bytes(r.read())
        got = sha256(dest)
        if got != want:
            raise SystemExit(f"ads {name}: sha256 mismatch {got} != {want}")
    return d


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
    for k in a.only or [*SOURCES, "uiuc_ads"]:
        p = fetch_coords(force=a.force) if k == "uiuc_ads" else fetch(k, force=a.force)
        print("ok", k, p.relative_to(ROOT.parent))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
