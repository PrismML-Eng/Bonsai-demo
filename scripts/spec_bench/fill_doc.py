#!/usr/bin/env python3
"""Replace every {{BENCH:key}} marker in a markdown document with a benchmark value.

The values come from placeholders.json (fill_placeholders.py). The script
reports the markers that have no value and the values that no marker uses.
It writes the document only when every marker has a value; with --check it
writes nothing. Standard library only.

Usage: fill_doc.py <doc.md> <placeholders.json> [--check] [--out FILE] [--strict]
Exit codes: 0 every marker filled (or --check found nothing missing),
1 a marker has no value (or a value is n/a with --strict), 2 usage error.
"""

import argparse
import json
import re
import sys

MARKER = re.compile(r"\{\{BENCH:([A-Za-z0-9_.\-]+)\}\}")
ANY_MARKER = re.compile(r"\{\{BENCH:")


def find_keys(text):
    """The marker keys in the document, in order of first appearance, without duplicates."""
    keys = []
    for match in MARKER.finditer(text):
        if match.group(1) not in keys:
            keys.append(match.group(1))
    return keys


def fill(text, values):
    """Return (filled text, missing keys). A key without a value keeps its marker."""
    missing = []

    def replace(match):
        key = match.group(1)
        if key in values:
            return str(values[key])
        if key not in missing:
            missing.append(key)
        return match.group(0)

    return MARKER.sub(replace, text), missing


def malformed_markers(text):
    """Every `{{BENCH:` start that is not a well-formed marker, as a short excerpt.

    This catches a key with a bad character, and also a marker that never
    closes, which the fill step would otherwise leave in the document.
    """
    bad = []
    for match in ANY_MARKER.finditer(text):
        start = match.start()
        if MARKER.match(text, start) is not None:
            continue
        end = text.find("}}", start)
        excerpt = text[start:end + 2] if 0 <= end - start <= 60 else text[start:start + 40]
        bad.append(excerpt.split("\n")[0])
    return bad


def report(text, values, strict=False):
    """Compare the document markers with the values. Return (problems, notes)."""
    keys = find_keys(text)
    problems = []
    notes = []
    missing = [k for k in keys if k not in values]
    if missing:
        problems.append("%d markers have no value: %s" % (len(missing), ", ".join(missing)))
    na = [k for k in keys if k in values and str(values[k]) == "n/a"]
    if na:
        line = "%d markers would print n/a: %s" % (len(na), ", ".join(na))
        (problems if strict else notes).append(line)
    unused = sorted(k for k in values if k not in keys)
    if unused:
        notes.append("%d values have no marker: %s" % (len(unused), ", ".join(unused)))
    malformed = malformed_markers(text)
    if malformed:
        problems.append("%d malformed markers: %s" % (len(malformed), ", ".join(malformed)))
    notes.insert(0, "%d markers, %d distinct keys, %d values" % (len(MARKER.findall(text)), len(keys), len(values)))
    return problems, notes


def parse_args(argv):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("doc", help="markdown document with {{BENCH:key}} markers")
    p.add_argument("placeholders", help="placeholders.json from fill_placeholders.py")
    p.add_argument("--check", action="store_true", help="report only; write nothing")
    p.add_argument("--out", default=None, help="write the filled document here instead of in place")
    p.add_argument("--strict", action="store_true", help="treat an n/a value as missing")
    return p.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    try:
        with open(args.doc, "r", encoding="utf-8") as f:
            text = f.read()
        with open(args.placeholders, "r", encoding="utf-8") as f:
            values = json.load(f)
    except (OSError, ValueError) as exc:
        print("fill_doc: %s" % exc, file=sys.stderr)
        return 2
    if not isinstance(values, dict):
        print("fill_doc: %s does not hold a JSON object" % args.placeholders, file=sys.stderr)
        return 2
    problems, notes = report(text, values, strict=args.strict)
    for line in notes:
        print("fill_doc: %s" % line)
    for line in problems:
        print("fill_doc: PROBLEM: %s" % line)
    if args.check:
        print("fill_doc: check only, nothing written")
        return 1 if problems else 0
    if problems:
        print("fill_doc: refused to write; fix the problems above")
        return 1
    filled, missing = fill(text, values)
    if missing or ANY_MARKER.search(filled):
        print("fill_doc: refused to write; markers would remain: %s" % ", ".join(missing), file=sys.stderr)
        return 1
    out = args.out or args.doc
    with open(out, "w", encoding="utf-8") as f:
        f.write(filled)
    print("fill_doc: wrote %s" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
