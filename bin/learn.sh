#!/usr/bin/env bash
# usage: learn.sh owner/repo#N  — merge human review comments of a reviewed PR into the repo mental model
set -u
TASTE_DIR=${TASTE_DIR:-$HOME/.taste}
PLUGIN=$(cd "$(dirname "$0")/.." && pwd)
ref=$1; repo=${ref%#*}; n=${ref#*#}
s=$TASTE_DIR/reviews/$repo/$n/status.json
[ -f "$s" ] || { echo "no review for $ref"; exit 1; }
cd "$TASTE_DIR/repos/$repo" && TASTE_DIR=$TASTE_DIR claude -p "/taste-reviewer:model learn $ref" \
  --plugin-dir "$PLUGIN" --permission-mode bypassPermissions \
  >> "$TASTE_DIR/logs/${repo//\//_}-$n.log" 2>&1
c=$(gh api "repos/$repo/pulls/$n" -q '.comments + .review_comments')
jq --argjson c "$c" --arg t "$(date -u +%FT%TZ)" '.learned_comments=$c|.learned=$t' "$s" > "$s.tmp" && mv "$s.tmp" "$s"
echo "learned $ref ($c comments)"
