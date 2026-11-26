#!/usr/bin/env python3
"""Assemble the standalone DaySpark prototype from the frozen master + host layers."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MASTER = ROOT / "dayspark-spec.html"
OUT = ROOT / "dayspark-prototype.html"
INDEX = ROOT / "index.html"
SRC = ROOT / "prototype"

html = MASTER.read_text(encoding="utf-8")
css = (SRC / "host.css").read_text(encoding="utf-8")
js_files = [SRC / "host.js"] + sorted(SRC.glob("flows-*.js"))
js = "\n\n".join(p.read_text(encoding="utf-8") for p in js_files if p.exists())
if "</script" in js.lower():
    raise SystemExit("prototype JS must not contain a closing script tag")

html = html.replace("<title>DaySpark · 视觉与交互规格母版</title>", "<title>DaySpark · 交互原型</title>", 1)
html = html.replace("</head>", f"<style>\n{css}\n</style>\n</head>", 1)
html = html.replace("</body>", f"<script>\n{js}\n</script>\n</body>", 1)
OUT.write_text(html, encoding="utf-8")
INDEX.write_text(html, encoding="utf-8")
print(f"wrote {OUT} and {INDEX} ({len(html):,} bytes) from {len(js_files)} script file(s)")
