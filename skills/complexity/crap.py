#!/usr/bin/env python3
"""CRAP = ccn^2 * (1-cov)^3 + ccn. Reads lizard --csv on stdin, coverage file as argv[1]."""
import csv, os, re, sys
import xml.etree.ElementTree as ET
from collections import defaultdict

CRAP_MAX = float(os.environ.get("CRAP_MAX", 30))


def _add(h, f, n, c):
    h[f][n] = max(h[f].get(n, 0), c)


def lcov(path):
    h, f = defaultdict(dict), None
    for ln in open(path, errors="ignore"):
        if ln.startswith("SF:"):
            f = ln[3:].strip()
        elif ln.startswith("DA:") and f:
            n, c = ln[3:].strip().split(",")[:2]
            _add(h, f, int(n), int(c))
    return h


def xmlcov(path):
    h = defaultdict(dict)
    root = ET.parse(path).getroot()
    for cl in root.iter("class"):                      # cobertura
        f = cl.get("filename")
        if f:
            for l in cl.iter("line"):
                _add(h, f, int(l.get("number")), int(float(l.get("hits", 0))))
    for fl in root.iter("file"):                       # clover
        f = fl.get("path") or fl.get("name")
        if f:
            for l in fl.iter("line"):
                n, c = l.get("num"), l.get("count")
                if n and c is not None:
                    _add(h, f, int(n), int(c))
    return h


def goprof(path):
    h = defaultdict(dict)
    for ln in open(path, errors="ignore"):
        m = re.match(r"(.+):(\d+)\.\d+,(\d+)\.\d+ \d+ (\d+)$", ln.strip())
        if m:
            for n in range(int(m.group(2)), int(m.group(3)) + 1):
                _add(h, m.group(1), n, int(m.group(4)))
    return h


def load(path):
    head = open(path, errors="ignore").read(200).lstrip()
    if head.startswith("<"):
        return xmlcov(path)
    if head.startswith("mode:"):
        return goprof(path)
    return lcov(path)


def norm(p):
    return os.path.normpath(p).lstrip("./")


def main():
    raw = load(sys.argv[1])
    idx = {norm(k): v for k, v in raw.items()}

    def find(f):
        t = norm(f)
        if t in idx:
            return idx[t]
        for k, v in idx.items():
            if k.endswith("/" + t) or t.endswith("/" + k):
                return v
        return None

    rows, missing, blank = [], set(), 0
    for r in csv.reader(sys.stdin):
        if len(r) < 11:
            continue
        ccn, f, fn, s, e = int(r[1]), r[6], r[7], int(r[9]), int(r[10])
        cov = find(f)
        if cov is None:
            missing.add(f)
            c, flag = 0.0, " *"
        else:
            lines = [n for n in range(s, e + 1) if n in cov]
            if not lines:
                blank += 1
                continue
            c = sum(1 for n in lines if cov[n] > 0) / len(lines)
            flag = ""
        rows.append((ccn ** 2 * (1 - c) ** 3 + ccn, f, s, fn, ccn, c, flag))

    rows.sort(reverse=True)
    over = [r for r in rows if r[0] > CRAP_MAX]
    print(f"functions: {len(rows)}   over CRAP>{CRAP_MAX:g}: {len(over)}")
    for crap, f, s, fn, ccn, c, flag in over:
        print(f"{f}:{s} {fn} — CRAP {crap:.0f} (CCN {ccn}, cov {c*100:.0f}%){flag}")
    if not over:
        print("  none over threshold")
    if missing:
        print(f"\n* not in coverage report, counted as 0%: {', '.join(sorted(missing))}")
    if blank:
        print(f"\n{blank} function(s) skipped: no executable lines in the coverage report")


main()
