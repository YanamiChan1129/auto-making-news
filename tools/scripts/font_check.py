import sys
import zipfile
from xml.etree import ElementTree as ET

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"


def inspect(path):
    z = zipfile.ZipFile(path)
    doc = z.read("word/document.xml").decode("utf-8")
    root = ET.fromstring(doc)
    seen = {}
    for r in root.findall(".//" + W + "r"):
        rPr = r.find(W + "rPr")
        if rPr is not None:
            rf = rPr.find(W + "rFonts")
            if rf is not None:
                k = (rf.get(W + "ascii"), rf.get(W + "eastAsia"), rf.get(W + "hAnsi"))
                seen[k] = seen.get(k, 0) + 1
    print("=== " + path.split("\\")[-1])
    print("run font combos:", seen)
    styles = z.read("word/styles.xml").decode("utf-8")
    import re

    m = re.search(r'w:ascii="([^"]+)"[^>]*w:eastAsia="([^"]+)"', styles)
    m2 = re.search(r'<w:rFonts w:ascii="([^"]+)"[^>]*/>', styles)
    print("styles ascii/eastAsia:", m.groups() if m else None)
    print("styles rFonts:", m2.groups() if m2 else None)
    print()


for p in sys.argv[1:]:
    inspect(p)
