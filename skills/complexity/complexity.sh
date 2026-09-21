#!/usr/bin/env bash
# Cyclomatic (lizard) + cognitive (complexipy) complexity for changed files.
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
uvx lizard -w -C "$CCN_MAX" "${files[@]}" 2>/dev/null | sed 's/ warning:/ /' | grep . || echo "  none over threshold"

py=(); for f in "${files[@]}"; do [[ $f == *.py ]] && py+=("$f"); done
if [ ${#py[@]} -gt 0 ]; then
  echo
  echo "## Cognitive (complexipy)"
  uvx complexipy --max-complexity-allowed "$COG_MAX" --failed --plain --sort desc "${py[@]}" 2>&1 | grep . | tail -40
fi
