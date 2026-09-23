#!/usr/bin/env python3
"""Keep only functions whose lines the branch changed.
  changed.py csv <base>                 lizard --csv on stdin -> rows that overlap changed lines
  changed.py cog <base> <max> <json>    complexipy json -> "path:line fn — COG n" over max, overlapping
"""
import ast, csv, re, subprocess, sys
from collections import defaultdict


def changed_lines(base):
    mb = subprocess.run(["git", "merge-base", base, "HEAD"], capture_output=True, text=True).stdout.strip()
    out = subprocess.run(["git", "diff", "-U0", f"{mb}...HEAD"], capture_output=True, text=True).stdout
    lines, f = defaultdict(set), None
    for ln in out.splitlines():
        if ln.startswith("+++ "):
            f = ln[6:] if ln.startswith("+++ b/") else None
        elif ln.startswith("@@") and f:
            m = re.search(r"\+(\d+)(?:,(\d+))?", ln)
            start, n = int(m.group(1)), int(m.group(2) or 1)
            lines[f].update(range(start, start + n))
    return lines


def overlaps(ch, f, a, b):
    return any(a <= x <= b for x in ch.get(f, ()))


def ranges(path):
    out = {}
    def walk(node, prefix):
        for c in ast.iter_child_nodes(node):
            if isinstance(c, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                name = f"{prefix}::{c.name}" if prefix else c.name
                if not isinstance(c, ast.ClassDef):
                    out[name] = (c.lineno, c.end_lineno)
                walk(c, name)
    walk(ast.parse(open(path).read()), "")
    return out


def main():
    mode, base = sys.argv[1], sys.argv[2]
    ch = changed_lines(base)
    if mode == "csv":
        w = csv.writer(sys.stdout)
        for r in csv.reader(sys.stdin):
            if len(r) >= 11 and overlaps(ch, r[6], int(r[9]), int(r[10])):
                w.writerow(r)
    elif mode == "cog":
        mx, data = int(sys.argv[3]), __import__("json").load(open(sys.argv[4]))
        cache, hits = {}, []
        for e in data:
            if e["complexity"] <= mx:
                continue
            p = e["path"]
            cache.setdefault(p, ranges(p))
            a, b = cache[p].get(e["function_name"], (0, -1))
            if overlaps(ch, p, a, b):
                hits.append((e["complexity"], f"{p}:{a} {e['function_name']} — COG {e['complexity']}"))
        for _, s in sorted(hits, reverse=True):
            print(s)
        if not hits:
            print("  none over threshold")


if __name__ == "__main__":
    main()
