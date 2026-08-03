import glob
import json
import os
import re
import sys
from collections import Counter

STATE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "state")
ARCHIVE_DIR = os.path.join(STATE_DIR, "daily_news")


def normalize(source):
    s = source.strip().lstrip("据").strip("：: ")
    s = re.sub(r"（.*?）", "", s).strip()
    return s or "未标注"


def summarize():
    if not os.path.isdir(ARCHIVE_DIR):
        print(f"no archive dir: {ARCHIVE_DIR}", file=sys.stderr)
        return 1

    counter = Counter()
    per_day = {}
    total = 0
    for path in sorted(glob.glob(os.path.join(ARCHIVE_DIR, "*.json"))):
        day = os.path.basename(path).split(".")[0]
        try:
            with open(path, "r", encoding="utf-8-sig") as f:
                data = json.load(f)
        except Exception as e:
            print(f"WARN: cannot parse {path}: {e}", file=sys.stderr)
            continue
        items = data.get("items", [])
        day_counter = Counter()
        for it in items:
            src = normalize(it.get("source", "未标注"))
            counter[src] += 1
            day_counter[src] += 1
            total += 1
        per_day[day] = day_counter

    print(f"== 新闻来源汇总（共 {total} 条，{len(per_day)} 天）==")
    print()
    print("按来源统计：")
    for src, n in counter.most_common():
        print(f"  {src}: {n}")
    print()
    print("按日期明细：")
    for day in sorted(per_day):
        parts = ", ".join(f"{s}x{n}" for s, n in per_day[day].most_common())
        print(f"  {day}: {parts or '无'}")
    return 0


if __name__ == "__main__":
    sys.exit(summarize())
