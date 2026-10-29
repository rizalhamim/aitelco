"""Lay each golden render next to its mockup frame.

    python3 tool/compare_mockups.py [out_dir]

Reads test/golden/out/<frame>.png and design/mockup/export/<frame>.png and
writes <out_dir>/<frame>.png: mockup | app | difference heat map, plus the
mean absolute pixel difference per frame on stdout.
"""
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageOps

ROOT = Path(__file__).resolve().parents[1]
MOCK = ROOT.parent / "design" / "mockup" / "export"
GOLD = ROOT / "test" / "golden" / "out"


def main() -> None:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build" / "mockup_compare"
    out.mkdir(parents=True, exist_ok=True)
    for g in sorted(GOLD.glob("*.png")):
        m = MOCK / g.name
        if not m.exists():
            continue
        a = Image.open(m).convert("RGB")
        b = Image.open(g).convert("RGB")
        if b.size != a.size:
            b = b.resize(a.size)
        diff = ImageChops.difference(a, b)
        score = sum(ImageOps.grayscale(diff).getdata()) / (a.size[0] * a.size[1])
        heat = ImageOps.autocontrast(ImageOps.grayscale(diff))
        sheet = Image.new("RGB", (a.size[0] * 3 + 40, a.size[1]), "white")
        sheet.paste(a, (0, 0))
        sheet.paste(b, (a.size[0] + 20, 0))
        sheet.paste(heat.convert("RGB"), (a.size[0] * 2 + 40, 0))
        sheet.save(out / g.name)
        print(f"{score:6.2f}  {g.stem}")


if __name__ == "__main__":
    main()
