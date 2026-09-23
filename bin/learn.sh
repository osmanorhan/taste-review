#!/usr/bin/env bash
# usage: learn.sh owner/repo#N  — merge human review comments of a reviewed PR into the repo mental model
set -u
TASTE_DIR=${TASTE_DIR:-$HOME/.taste}
PLUGIN=$(cd "$(dirname "$0")/.." && pwd)
ref=$1; repo=${ref%#*}; n=${ref#*#}
s=$TASTE_DIR/reviews/$repo/$n/status.json
[ -f "$s" ] || { echo "no review for $ref"; exit 1; }
cd "$TASTE_DIR/repos/$repo" && TASTE_DIR=$TASTE_DIR claude -p "/taste-reviewer:model learn $ref" \
  --plugin-dir "$PLUGIN" --settings '{"enabledPlugins":{"taste-reviewer@taste-reviewer":false}}' --permission-mode bypassPermissions \
  --output-format stream-json --verbose >> "$TASTE_DIR/logs/${repo//\//_}-$n-learn.jsonl" 2>&1
pr=$(gh api "repos/$repo/pulls/$n" -q '{c: (.comments + .review_comments), merged: .merged}')
jq --argjson p "$pr" --arg t "$(date -u +%FT%TZ)" '.learned_comments=$p.c|.learned_merged=$p.merged|.learned=$t' "$s" > "$s.tmp" && mv "$s.tmp" "$s"
echo "learned $ref ($(jq -c . <<<"$pr"))"
