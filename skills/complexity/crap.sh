#!/usr/bin/env bash
# CRAP score for functions changed in this branch. Needs a coverage report.
# usage: crap.sh [base-ref] [coverage-file]
set -u

base=${1:-}
cov=${2:-${COV_FILE:-}}

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

if [ -z "$cov" ]; then
  for c in coverage/lcov.info lcov.info coverage.xml build/logs/clover.xml clover.xml \
           coverage/clover.xml coverage/cobertura-coverage.xml coverage.out cover.out; do
    [ -f "$c" ] && cov=$c && break
  done
fi
[ -z "$cov" ] && { echo "no coverage report found (looked for lcov.info, coverage.xml, clover.xml, coverage.out). Pass one: crap.sh '' path/to/report"; exit 1; }
[ -f "$cov" ] || { echo "coverage file not found: $cov"; exit 1; }

files=()
while IFS= read -r f; do files+=("$f"); done < <(git diff --name-only --diff-filter=d "$(git merge-base "$base" HEAD)"...HEAD \
  | grep -Ei '\.(py|js|jsx|ts|tsx|java|go|php|rb|cs|c|cc|cpp|h|hpp|swift|kt|scala|rs|lua)$')
[ ${#files[@]} -eq 0 ] && { echo "no code files changed vs $base"; exit 0; }

echo "base: $base   coverage: $cov   files: ${#files[@]}"
echo
echo "## CRAP (ccn^2 * (1-cov)^3 + ccn)"
uvx lizard --csv "${files[@]}" 2>/dev/null | python3 ~/.claude/skills/complexity/crap.py "$cov"
