#!/usr/bin/env bash
# Poll GitHub. New head sha on a requested PR or on a set member -> review. New human comments on a reviewed PR -> learn.
set -u
TASTE_DIR=${TASTE_DIR:-$HOME/.taste}
BIN=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$TASTE_DIR"
[ -d "$TASTE_DIR/.git" ] || git -C "$TASTE_DIR" init -q
mkdir "$TASTE_DIR/lock" 2>/dev/null || { echo "another watch is running"; exit 0; }
trap 'rmdir "$TASTE_DIR/lock"' EXIT
head_sha() { gh pr view "${1#*#}" --repo "${1%#*}" --json headRefOid -q .headRefOid; }
insets=$(jq -r '.prs|keys[]' "$TASTE_DIR"/reviews/_sets/*/status.json 2>/dev/null)

gh search prs --review-requested=@me --state=open --limit 50 --json repository,number \
  -q '.[] | "\(.repository.nameWithOwner)#\(.number)"' | while read -r ref; do
  grep -qxF "$ref" <<<"$insets" && continue
  s=$TASTE_DIR/reviews/${ref%#*}/${ref#*#}/status.json
  sha=$(head_sha "$ref")
  if [ -f "$s" ] && [ "$(jq -r .sha "$s")" = "$sha" ] && [ "$(jq -r .status "$s")" != failed ]; then continue; fi
  echo "$(date -u +%FT%TZ) review $ref @ ${sha:0:7}"
  "$BIN/run.sh" "$ref"
done

for s in "$TASTE_DIR"/reviews/_sets/*/status.json; do
  [ -f "$s" ] || continue
  refs=$(jq -r '.prs|keys_unsorted[]' "$s")
  stale=$([ "$(jq -r .status "$s")" = failed ] && echo 1)
  for ref in $refs; do [ "$(head_sha "$ref")" = "$(jq -r --arg r "$ref" '.prs[$r].sha' "$s")" ] || stale=1; done
  [ -n "$stale" ] || continue
  echo "$(date -u +%FT%TZ) review set" $refs
  "$BIN/run.sh" $refs
done

learn() {  # ref status-file jq-path
  pr=$(gh api "repos/${1%#*}/pulls/${1#*#}" -q '{c: (.comments + .review_comments), merged: .merged}' 2>/dev/null) || return
  c=$(jq -r .c <<<"$pr"); merged=$(jq -r .merged <<<"$pr")
  new_comments=$([ "$c" -gt "$(jq -r "$3 | .learned_comments // 0" "$2")" ] && echo 1 || echo 0)
  new_merge=$([ "$merged" = true ] && [ "$(jq -r "$3 | .learned_merged // false" "$2")" != true ] && echo 1 || echo 0)
  [ "$new_comments" = 1 ] || [ "$new_merge" = 1 ] || return
  echo "$(date -u +%FT%TZ) learn $1 (comments=$c merged=$merged)"
  "$BIN/learn.sh" "$1" "$2" "$3"
}
for s in "$TASTE_DIR"/reviews/*/*/*/status.json "$TASTE_DIR"/reviews/_sets/*/status.json; do
  [ -f "$s" ] || continue
  st=$(jq -r .status "$s"); [ "$st" = done ] || [ "$st" = posted ] || continue
  if jq -e .set "$s" >/dev/null; then
    for ref in $(jq -r '.prs|keys_unsorted[]' "$s"); do learn "$ref" "$s" ".prs[\"$ref\"]"; done
  else
    learn "$(jq -r '"\(.repo)#\(.number)"' "$s")" "$s" .
  fi
done
