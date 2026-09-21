#!/usr/bin/env bash
# Poll GitHub for PRs where my review is requested. Run a review when head sha is new.
set -u
TASTE_DIR=${TASTE_DIR:-$HOME/.taste}
BIN=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$TASTE_DIR"
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
