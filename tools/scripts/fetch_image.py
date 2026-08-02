import argparse
import os
import ssl
import sys
import urllib.request
from urllib.parse import urlparse

ssl_context = ssl.create_default_context()

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
    "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
}

MIN_SIZE = 10240
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp"}


def download(url: str, out_path: str) -> bool:
    try:
        req = urllib.request.Request(url, headers=HEADERS)
        with urllib.request.urlopen(req, timeout=20, context=ssl_context) as resp:
            ctype = resp.headers.get("Content-Type", "")
            data = resp.read()
        if not ctype.startswith("image/"):
            print(f"FAIL {url}: Content-Type={ctype}", flush=True)
            return False
        if len(data) < MIN_SIZE:
            print(f"FAIL {url}: too small {len(data)} bytes", flush=True)
            return False
        ext = os.path.splitext(urlparse(url).path)[1].lower()
        if ext not in IMAGE_EXT:
            ext = ".jpg"
        if not out_path.lower().endswith(ext):
            out_path = out_path + ext
        os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
        with open(out_path, "wb") as f:
            f.write(data)
        print(f"OK {url} -> {out_path} ({len(data)} bytes)", flush=True)
        return True
    except Exception as e:
        print(f"FAIL {url}: {e}", flush=True)
        return False


def main() -> int:
    p = argparse.ArgumentParser(description="Download and validate news images")
    p.add_argument("--url", action="append", required=True, help="image URL (repeatable)")
    p.add_argument("--out", required=True, help="output path prefix, e.g. tmp/img_1")
    p.add_argument("--insecure", action="store_true", help="skip TLS cert verification (not recommended)")
    args = p.parse_args()

    if args.insecure:
        global ssl_context
        ssl_context = ssl._create_unverified_context()

    for i, url in enumerate(args.url, start=1):
        out = args.out if len(args.url) == 1 else f"{args.out}_{i}"
        if not download(url, out):
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
