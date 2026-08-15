"""Build a docx article from a single meta JSON to avoid CLI Unicode arg issues.
meta.json format:
{
  "title": "...",
  "output": "C:\\path\\to\\out.docx",
  "body": "path to body json (subtitle/paragraphs/captions)",
  "images": ["img1.jpg", "img2.jpg", "img3.jpg"]
}
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_docx import build


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--meta", required=True, help="path to meta json")
    args = p.parse_args()

    with open(args.meta, "r", encoding="utf-8-sig") as f:
        meta = json.load(f)
    with open(meta["body"], "r", encoding="utf-8-sig") as f:
        body = json.load(f)

    build(
        meta["title"],
        meta["output"],
        body.get("paragraphs", []),
        meta.get("images", []),
        subtitle=body.get("subtitle"),
        captions=body.get("captions", []),
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
