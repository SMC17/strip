"""CLI entrypoints."""

from __future__ import annotations

import argparse
from pathlib import Path

from .gallery import write_gallery
from .teachers import jsbsim_stub, neuralfoil_stub, openvsp_stub, vspaero_l1


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="strip_uas_v0")
    sub = p.add_subparsers(dest="cmd", required=True)

    run = sub.add_parser("run-search", help="Run search gallery")
    run.add_argument("--parents", type=int, default=5)
    run.add_argument("--steps", type=int, default=40)
    run.add_argument("--seed", type=int, default=0)
    run.add_argument("--out", type=Path, default=Path("out/gallery"))
    run.add_argument(
        "--no-neuralfoil",
        action="store_true",
        help="Force analytic L1 polar even if neuralfoil is installed",
    )
    run.add_argument(
        "--vspaero",
        action="store_true",
        help=(
            "Drive DesignSearchEnv reward from VSPAERO CL/CD when "
            "vspscript+vspaero available (skips cleanly otherwise)"
        ),
    )

    det = sub.add_parser("detect-teachers", help="Probe aero teacher availability")

    args = p.parse_args(argv)
    if args.cmd == "run-search":
        manifest = write_gallery(
            args.out,
            n_parents=args.parents,
            steps=args.steps,
            seed=args.seed,
            prefer_neuralfoil=not args.no_neuralfoil,
            prefer_vspaero=args.vspaero,
        )
        print(
            f"Wrote {args.out} improved={manifest['n_improved']} "
            f"best_dLD={manifest['best_delta_ld']:.6f} "
            f"vspaero={manifest.get('prefer_vspaero')}"
        )
        return 0
    if args.cmd == "detect-teachers":
        for name, mod in (
            ("neuralfoil", neuralfoil_stub),
            ("jsbsim", jsbsim_stub),
            ("openvsp", openvsp_stub),
            ("vspaero", vspaero_l1),
        ):
            d = mod.detect().to_dict()
            print(f"{name}: available={d.get('available')} {d}")
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
