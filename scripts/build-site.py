#!/usr/bin/env python3
"""Build site/index.html (a full HTML document for Vercel or any static host)
from site/course.html (the page body, which is also published as-is as a
claude.ai Artifact). Run after editing course.html: python3 scripts/build-site.py
"""
from pathlib import Path

SITE = Path(__file__).resolve().parent.parent / "site"
src = (SITE / "course.html").read_text()
split = src.index('<div class="wrap">')
head, body = src[:split], src[split:]
page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="description" content="A hands-on ladder course in Cedar, Dogwood, automated reasoning and Lean for governing AI agents across the PDLC, SDLC and ADLC.">
<style>:root{{color-scheme:light;padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}}body{{margin:0}}img{{max-width:100%}}[hidden]{{display:none!important}}</style>
{head.strip()}
</head>
<body>
{body.strip()}
</body>
</html>
"""
(SITE / "index.html").write_text(page)
print(f"wrote {SITE / 'index.html'} ({len(page):,} bytes)")
