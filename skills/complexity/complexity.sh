#!/usr/bin/env bash
# Cyclomatic (lizard) + cognitive (complexipy) complexity for functions this branch changed.
# usage: complexity.sh [base-ref]   default base: origin/develop or origin/main
set -u

CCN_MAX=${CCN_MAX:-10}
COG_MAX=${COG_MAX:-15}

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

files=()
while IFS= read -r f; do files+=("$f"); done < <(git diff --name-only --diff-filter=d "$(git merge-base "$base" HEAD)"...HEAD \
  | grep -Ei '\.(py|js|jsx|ts|tsx|java|go|php|rb|cs|c|cc|cpp|h|hpp|swift|kt|scala|rs|lua)$')
[ ${#files[@]} -eq 0 ] && { echo "no code files changed vs $base"; exit 0; }

echo "base: $base   files: ${#files[@]}   thresholds: CCN>$CCN_MAX  COG>$COG_MAX"
echo
echo "## Cyclomatic (lizard)"
H=$(dirname "$0")
uvx lizard --csv "${files[@]}" 2>/dev/null | python3 "$H/changed.py" csv "$base" \
  | python3 -c 'import csv,sys
m=int(sys.argv[1]); rows=[r for r in csv.reader(sys.stdin) if int(r[1])>m]
for r in sorted(rows,key=lambda r:-int(r[1])): print(f"{r[6]}:{r[9]} {r[7]} — CCN {r[1]}")
print("  none over threshold") if not rows else None' "$CCN_MAX"

py=(); for f in "${files[@]}"; do [[ $f == *.py ]] && py+=("$f"); done
if [ ${#py[@]} -gt 0 ]; then
  echo
  echo "## Cognitive (complexipy)"
  j=$(mktemp); uvx complexipy --output-format json --output "$j" "${py[@]}" >/dev/null 2>&1
  python3 "$H/changed.py" cog "$base" "$COG_MAX" "$j"; rm -f "$j"
fi
