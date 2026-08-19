import sys
import hashlib
import zipfile
import io
from docx import Document

EXPECTED_IMAGE_COUNT = 3
EXPECTED_BODY_PARAS = 7
MIN_BODY_CHARS = 1500
MAX_BODY_CHARS = 1900
BAD_MARKERS = ("captions_placeholder", "placeholder", "Lorem ipsum", "TBD", "待补充")
DHASH_DUP_THRESHOLD = 4


def _dhash(data):
    from PIL import Image
    im = Image.open(io.BytesIO(data)).convert("L").resize((9, 8))
    px = list(im.getdata())
    bits = []
    for y in range(8):
        for x in range(8):
            bits.append("1" if px[y * 9 + x] > px[y * 9 + x + 1] else "0")
    return "".join(bits)


def _hamming(a, b):
    return sum(x != y for x, y in zip(a, b))


def check_duplicate_images(path):
    problems = []
    items = []
    with zipfile.ZipFile(path) as z:
        for n in sorted(z.namelist()):
            if n.startswith("word/media/"):
                data = z.read(n)
                items.append((n, hashlib.md5(data).hexdigest(), data))
    for i in range(len(items)):
        for j in range(i + 1, len(items)):
            n1, h1, d1 = items[i]
            n2, h2, d2 = items[j]
            if h1 == h2:
                problems.append(f"duplicate image (identical): {n1} == {n2}")
                continue
            try:
                if _hamming(_dhash(d1), _dhash(d2)) <= DHASH_DUP_THRESHOLD:
                    problems.append(f"duplicate image (visually same, different size/encoding): {n1} ~ {n2}")
            except Exception:
                pass
    return problems


def verify(path):
    problems = []
    try:
        doc = Document(path)
    except Exception as e:
        return [f"cannot open docx: {e}"]

    paras = [p.text.strip() for p in doc.paragraphs]

    if len(paras) != 17:
        problems.append(f"paragraph count {len(paras)} != 17 (title+2subtitle+7body+3img+3caption+signature)")

    title = paras[0] if paras else ""
    if not title:
        problems.append("missing title (para 0 empty)")

    subtitle = paras[1] if len(paras) > 1 else ""
    if not subtitle or "国际观察" not in subtitle:
        problems.append(f"missing subtitle bar (para 1): {subtitle!r}")
    if len(paras) > 2 and not paras[2]:
        problems.append("missing subtitle summary line (para 2 empty)")

    body = paras[3:17]
    body = [t for t in body if t and "图｜" not in t and t not in ("火星前哨站",)]
    if len(body) != EXPECTED_BODY_PARAS:
        problems.append(f"body paragraphs {len(body)} != {EXPECTED_BODY_PARAS}")

    body_chars = sum(len(t) for t in body)
    if body_chars < MIN_BODY_CHARS or body_chars > MAX_BODY_CHARS:
        problems.append(f"body total chars {body_chars} outside range {MIN_BODY_CHARS}-{MAX_BODY_CHARS}")

    captions = [t for t in paras if t.startswith("图｜")]
    if len(captions) != 3:
        problems.append(f"captions {len(captions)} != 3")

    has_signature = any(t == "火星前哨站" for t in paras)
    if not has_signature:
        problems.append("missing signature '火星前哨站'")

    for marker in BAD_MARKERS:
        if any(marker in t for t in paras):
            problems.append(f"bad marker '{marker}' found in content")

    n_images = len(doc.inline_shapes)
    if n_images != EXPECTED_IMAGE_COUNT:
        problems.append(f"inline images {n_images} != {EXPECTED_IMAGE_COUNT}")

    problems.extend(check_duplicate_images(path))

    return problems


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: verify_docx.py <docx> [<docx> ...]", file=sys.stderr)
        return 2
    rc = 0
    for path in sys.argv[1:]:
        problems = verify(path)
        if problems:
            rc = 1
            print(f"FAIL {path}:")
            for p in problems:
                print(f"  - {p}")
        else:
            print(f"PASS {path}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
