#!/usr/bin/env python3
"""Emit canonical bibliographic extraction artifacts and digests for primary sources."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "sources" / "primary-sources.json"
EXTRACTED = ROOT / "sources" / "extracted"


def canonical_bibliographic(record: dict) -> str:
    payload = {
        "schema": "strip.extracted.bibliographic.v0",
        "id": record["id"],
        "title": record["title"],
        "publisher": record["publisher"],
        "edition": record["edition"],
        "version": record["version"],
        "license": record["license"],
        "retrieved_at": record["retrieved_at"],
    }
    return json.dumps(payload, separators=(",", ":"), sort_keys=True)


def sha256_hex(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def main() -> None:
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    EXTRACTED.mkdir(parents=True, exist_ok=True)
    updated = 0
    for record in data["records"]:
        if record.get("digest_scope") in {"source_content", "fixture_content"}:
            continue
        body = canonical_bibliographic(record)
        out = EXTRACTED / f"{record['id']}.bibliographic.json"
        out.write_text(body, encoding="utf-8", newline="\n")
        digest = f"sha256:{sha256_hex(body)}"
        rel = f"sources/extracted/{record['id']}.bibliographic.json"
        record["digest"] = digest
        record["digest_scope"] = "source_content"
        record["extraction"] = (
            f"Bibliographic metadata transcribed into {rel}; URL is locator only, not digest input."
        )
        record["extraction_provenance"] = {
            "citation_anchor": record["url"],
            "extracted_artifact_path": rel,
            "extracted_artifact_digest": digest,
            "normalization_script": "tools/gen_bibliographic_extractions.py",
        }
        limitations = list(record.get("limitations", []))
        limitations = [
            item
            for item in limitations
            if "Digest covers the UTF-8 locator URL" not in item
        ]
        limitations.append(
            "Digest covers canonical bibliographic JSON only; no report body or measurements copied."
        )
        record["limitations"] = limitations[:16]
        updated += 1
        print(f"{record['id']}: {digest}")
    MANIFEST.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"updated {updated} records in {MANIFEST}")


if __name__ == "__main__":
    main()
