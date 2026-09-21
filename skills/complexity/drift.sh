#!/usr/bin/env bash
# LLM-drift check: slop patterns on the lines this branch ADDED.
# usage: drift.sh [base-ref]
set -u

COMMENT_RATIO_MAX=${COMMENT_RATIO_MAX:-25}   # % of added lines that are # comments
COMMENT_BLOCK_MAX=${COMMENT_BLOCK_MAX:-2}    # max lines in a comment or docstring block

base=${1:-}
if [ -z "$base" ]; then
  b=$(gh pr view --json baseRefName -q .baseRefName 2>/dev/null)
  [ -n "$b" ] && git rev-parse --verify -q "origin/$b" >/dev/null && base="origin/$b"
fi
if [ -z "$base" ]; then
  for c in origin/develop origin/main origin/master develop main; do
    git rev-parse --verify -q "$c" >/dev/null && base=$c && break
  done
fi
[ -z "$base" ] && { echo "no base ref found"; exit 1; }
mb=$(git merge-base "$base" HEAD)

git diff -U0 "$mb"...HEAD > /tmp/.drift.diff
python3 - "$mb" "$COMMENT_RATIO_MAX" "$COMMENT_BLOCK_MAX" <<'PY'
import re, subprocess, sys, collections
mb, ratio_max, block_max = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])

added = collections.defaultdict(set)      # file -> {lineno}
lines = collections.defaultdict(list)     # file -> [(lineno, text)]
cur, ln = None, 0
for raw in open('/tmp/.drift.diff', encoding='utf-8', errors='replace'):
    if raw.startswith('+++ b/'):
        cur = raw[6:].rstrip('\n')
    elif raw.startswith('@@'):
        m = re.search(r'\+(\d+)', raw); ln = int(m.group(1)) if m else 0
    elif raw.startswith('+') and cur:
        added[cur].add(ln); lines[cur].append((ln, raw[1:].rstrip('\n'))); ln += 1

if not added:
    print("no added lines vs base"); sys.exit(0)

CODE = re.compile(r'\.(py|js|jsx|ts|tsx|java|go|php|rb|cs|c|cc|cpp|h|hpp|swift|kt|scala|rs)$', re.I)
def is_comment(t):
    s = t.strip()
    return s.startswith('#') or s.startswith('//')

print("## Comment drift (added lines only)")
hits = 0
for f, ls in sorted(lines.items()):
    if not CODE.search(f): continue

    run, start = 0, None
    for n, t in ls:
        if is_comment(t):
            run += 1; start = start or n
        else:
            if run > block_max: print(f"  {f}:{start}: {run}-line comment block"); hits += 1
            run, start = 0, None
    if run > block_max: print(f"  {f}:{start}: {run}-line comment block"); hits += 1

    if f.endswith('.py'):
        try:
            tree = __import__('ast').parse(open(f, encoding='utf-8').read())
        except Exception:
            tree = None
        if tree is not None:
            ast = __import__('ast')
            for node in ast.walk(tree):
                if not isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
                    continue
                if ast.get_docstring(node, clean=False) is None: continue
                d = node.body[0]
                n = d.end_lineno - d.lineno + 1
                if n > block_max and added[f] & set(range(d.lineno, d.end_lineno + 1)):
                    kind = 'module' if isinstance(node, ast.Module) else getattr(node, 'name', '?')
                    print(f"  {f}:{d.lineno}: {n}-line docstring ({kind})"); hits += 1

    body = [t for _, t in ls if t.strip()]
    if len(body) >= 10:
        c = sum(1 for t in body if is_comment(t))
        pct = round(100 * c / len(body))
        if pct > ratio_max:
            print(f"  {f}: {pct}% of {len(body)} added lines are comments"); hits += 1
if not hits: print("  clean")

py = [f for f in added if f.endswith('.py')]
if py:
    RULES = "ERA001,F401,F841,ARG,RET504,RET505,SIM,PLR0913,PLR0911,PIE,C4"
    r = subprocess.run(
        ["uvx", "ruff", "check", "--no-cache", "--isolated", "--select", RULES,
         *sum(([ "--per-file-ignores", f"**/test*:{c}" ] for c in ("ARG","PLR0913","ERA001")), []),
         "--output-format", "concise", *py],
        capture_output=True, text=True)
    if r.returncode > 1: print("  ruff error:", r.stderr.strip()[:200])
    out = r.stdout
    print("\n## Slop patterns (ruff, added lines only)")
    n = 0
    for line in out.splitlines():
        m = re.match(r'^(.+?):(\d+):\d+: (.*)$', line)
        if m and int(m.group(2)) in added.get(m.group(1), ()):
            print(f"  {m.group(1)}:{m.group(2)}: {m.group(3)}"); n += 1
    if not n: print("  clean")
PY
