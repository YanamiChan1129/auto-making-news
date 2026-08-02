import json
import os
import sys
from datetime import date, datetime, timedelta

STATE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "state")
FULL = os.path.join(STATE_DIR, "written_topics.json")
RECENT = os.path.join(STATE_DIR, "recent_topics.json")
WINDOW_DAYS = 15


def load(path):
    if not os.path.exists(path):
        return []
    with open(path, "r", encoding="utf-8-sig") as f:
        return json.load(f)


def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def main():
    cutoff = date.today() - timedelta(days=WINDOW_DAYS)
    recent = []
    dropped = 0
    for item in load(FULL):
        try:
            d = datetime.fromisoformat(item.get("date", "")).date()
        except ValueError:
            dropped += 1
            print(f"WARN: dropped invalid entry (date missing/bad): {item!r}", file=sys.stderr)
            continue
        if d >= cutoff:
            recent.append(item)
    save(RECENT, recent)
    print(f"recent_topics.json: {len(recent)} topics in last {WINDOW_DAYS} days, {dropped} dropped")


if __name__ == "__main__":
    sys.exit(main())
