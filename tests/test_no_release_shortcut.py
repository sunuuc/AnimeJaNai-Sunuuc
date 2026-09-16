from pathlib import Path
root = Path(__file__).resolve().parents[1]
for rel in ("portable_config/input.conf", "portable_config/input-animejanai.conf"):
    text = (root / rel).read_text(encoding="utf-8-sig").lower()
    assert "animejanai-update" not in text, rel
    assert "ctrl+u" not in text, rel
assert not (root / "portable_config/scripts/animejanai_update.lua").exists()
updater = (root / "tools/standalone/Updater.cs").read_text(encoding="utf-8")
for token in ("--open-releases", "MANUAL_UPDATE", "github.com/sunuuc/AnimeJaNai-zh-CN/releases"):
    assert token not in updater, token
publish = (root / "tools/standalone/publish.py").read_text(encoding="utf-8")
assert "readme=R/'README.md'" not in publish
print("release-page shortcut absent")
