#!/usr/bin/env bash
# Poll GitHub. New head sha on a requested PR -> review. New human comments on a reviewed PR -> learn.
set -u
TASTE_DIR=${TASTE_DIR:-$HOME/.taste}
BIN=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$TASTE_DIR"
[ -d "$TASTE_DIR/.git" ] || git -C "$TASTE_DIR" init -q
mkdir "$TASTE_DIR/lock" 2>/dev/null || { echo "another watch is running"; exit 0; }
trap 'rmdir "$TASTE_DIR/lock"' EXIT

gh search prs --review-requested=@me --state=open --limit 50 --json repository,number \
  -q '.[] | "\(.repository.nameWithOwner)#\(.number)"' | while read -r ref; do
  repo=${ref%#*}; n=${ref#*#}
  s=$TASTE_DIR/reviews/$repo/$n/status.json
  sha=$(gh pr view "$n" --repo "$repo" --json headRefOid -q .headRefOid)
  if [ -f "$s" ] && [ "$(jq -r .sha "$s")" = "$sha" ] && [ "$(jq -r .status "$s")" != failed ]; then continue; fi
  echo "$(date -u +%FT%TZ) review $ref @ ${sha:0:7}"
  "$BIN/run.sh" "$ref"
done

for s in "$TASTE_DIR"/reviews/*/*/*/status.json; do
  [ -f "$s" ] || continue
  st=$(jq -r .status "$s"); [ "$st" = done ] || [ "$st" = posted ] || continue
  repo=$(jq -r .repo "$s"); n=$(jq -r .number "$s")
  pr=$(gh api "repos/$repo/pulls/$n" -q '{c: (.comments + .review_comments), merged: .merged}' 2>/dev/null) || continue
  c=$(jq -r .c <<<"$pr"); merged=$(jq -r .merged <<<"$pr")
  new_comments=$([ "$c" -gt "$(jq -r '.learned_comments // 0' "$s")" ] && echo 1 || echo 0)
  new_merge=$([ "$merged" = true ] && [ "$(jq -r '.learned_merged // false' "$s")" != true ] && echo 1 || echo 0)
  [ "$new_comments" = 1 ] || [ "$new_merge" = 1 ] || continue
  echo "$(date -u +%FT%TZ) learn $repo#$n (comments=$c merged=$merged)"
  "$BIN/learn.sh" "$repo#$n"
done
