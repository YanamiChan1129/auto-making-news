"""Verify a built docx using paths from a meta JSON (avoids CLI Unicode arg issues).
meta.json format: {"output": "path\\to\\out.docx", ...}
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from verify_docx import verify


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--meta", required=True, help="path to meta json")
    args = p.parse_args()

    with open(args.meta, "r", encoding="utf-8-sig") as f:
        meta = json.load(f)

    path = meta["output"]
    problems = verify(path)
    if problems:
        print(f"FAIL {path}:")
        for prob in problems:
            print(f"  - {prob}")
        return 1
    print(f"PASS {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
