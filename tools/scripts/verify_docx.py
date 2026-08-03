import sys
from docx import Document

EXPECTED_IMAGE_COUNT = 3
EXPECTED_BODY_PARAS = 6
MIN_BODY_CHARS = 1300
MAX_BODY_CHARS = 1700
BAD_MARKERS = ("captions_placeholder", "placeholder", "Lorem ipsum", "TBD", "待补充")


def verify(path):
    problems = []
    try:
        doc = Document(path)
    except Exception as e:
        return [f"cannot open docx: {e}"]

    paras = [p.text.strip() for p in doc.paragraphs]

    if len(paras) != 15:
        problems.append(f"paragraph count {len(paras)} != 15 (title+subtitle+6body+3img+3caption+signature)")

    title = paras[0] if paras else ""
    if not title:
        problems.append("missing title (para 0 empty)")

    subtitle = paras[1] if len(paras) > 1 else ""
    if not subtitle or "国际观察" not in subtitle:
        problems.append(f"missing subtitle bar (para 1): {subtitle!r}")

    body = paras[2:15]
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
