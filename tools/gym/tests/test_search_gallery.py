from pathlib import Path

from strip_uas_v0.gallery import write_gallery


def test_gallery_runs(tmp_path: Path):
    manifest = write_gallery(
        tmp_path, n_parents=2, steps=8, seed=0, prefer_neuralfoil=False
    )
    assert manifest["n_results"] >= 4
    assert (tmp_path / "summary.md").exists()
    assert (tmp_path / "manifest.json").exists()
