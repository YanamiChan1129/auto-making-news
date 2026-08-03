import argparse
import json
import os
import sys
from datetime import datetime

STATE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "state")
ARCHIVE_DIR = os.path.join(STATE_DIR, "daily_news")


def load_items(path_or_json):
    if os.path.exists(path_or_json):
        with open(path_or_json, "r", encoding="utf-8-sig") as f:
            return json.load(f)
    return json.loads(path_or_json)


def save_json(date_str, items):
    path = os.path.join(ARCHIVE_DIR, f"{date_str}.json")
    os.makedirs(ARCHIVE_DIR, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"date": date_str, "items": items}, f, ensure_ascii=False, indent=2)
    return path


def save_md(date_str, items):
    path = os.path.join(ARCHIVE_DIR, f"{date_str}.md")
    os.makedirs(ARCHIVE_DIR, exist_ok=True)
    lines = [f"# 国际新闻选题存档 · {date_str}", ""]
    for i, it in enumerate(items, start=1):
        lines.append(f"## {i}. {it.get('title', '')}")
        if it.get("keywords"):
            lines.append(f"- 主题关键词：{it['keywords']}")
        if it.get("summary"):
            lines.append(f"- 摘要：{it['summary']}")
        if it.get("source"):
            lines.append(f"- 来源：{it['source']}")
        lines.append("")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    return path


def main() -> int:
    p = argparse.ArgumentParser(description="Archive the 5 selected daily news items as JSON + Markdown")
    p.add_argument("--date", required=True, help="YYYY-MM-DD")
    p.add_argument("--items", required=True, help="path to JSON file or inline JSON array of items")
    args = p.parse_args()

    items = load_items(args.items)
    if len(items) != 5:
        print(f"WARN: expected 5 items, got {len(items)}", file=sys.stderr)

    j = save_json(args.date, items)
    m = save_md(args.date, items)
    print(f"archived {len(items)} items -> {j}")
    print(f"archived markdown -> {m}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
