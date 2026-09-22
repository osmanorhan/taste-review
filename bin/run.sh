#!/usr/bin/env bash
# usage: run.sh owner/repo#N
set -u
TASTE_DIR=${TASTE_DIR:-$HOME/.taste}
PLUGIN=$(cd "$(dirname "$0")/.." && pwd)
ref=$1; repo=${ref%#*}; n=${ref#*#}
out=$TASTE_DIR/reviews/$repo/$n
mkdir -p "$out" "$TASTE_DIR/repos/$repo" "$TASTE_DIR/logs" "$TASTE_DIR/model/${repo%/*}"
[ -d "$TASTE_DIR/.git" ] || git -C "$TASTE_DIR" init -q

meta=$(gh pr view "$n" --repo "$repo" --json title,headRefOid,baseRefName,author,url) || { echo "gh failed for $ref"; exit 1; }
sha=$(jq -r .headRefOid <<<"$meta"); base=$(jq -r .baseRefName <<<"$meta")
jq -n --arg repo "$repo" --arg n "$n" --arg sha "$sha" --arg base "$base" --argjson m "$meta" --arg t "$(date -u +%FT%TZ)" \
  '{repo:$repo,number:($n|tonumber),sha:$sha,base:$base,title:$m.title,author:$m.author.login,url:$m.url,status:"running",started:$t}' > "$out/status.json"

fail() { jq --arg e "$1" '.status="failed"|.error=$e' "$out/status.json" > "$out/.s" && mv "$out/.s" "$out/status.json"; echo "$ref failed: $1"; exit 1; }

wd=$TASTE_DIR/repos/$repo
[ -d "$wd/.git" ] || gh repo clone "$repo" "$wd" -- -q || fail "clone failed"
git -C "$wd" checkout -q --detach 2>/dev/null
git -C "$wd" fetch -qf origin "$base:refs/remotes/origin/$base" "pull/$n/head" || fail "fetch failed"
git -C "$wd" reset -q --hard "$sha" || fail "sha $sha not in checkout"
git -C "$wd" clean -qfd
[ "$(git -C "$wd" rev-parse HEAD)" = "$sha" ] || fail "checkout is not at $sha"

cd "$wd" && TASTE_DIR=$TASTE_DIR claude -p "/taste-reviewer:taste-review $ref" \
  --plugin-dir "$PLUGIN" --permission-mode bypassPermissions \
  > "$TASTE_DIR/logs/${repo//\//_}-$n.log" 2>&1
rc=$?

if [ ! -s "$out/review.md" ] || [ "$(jq -r .status "$out/status.json")" = running ]; then
  jq --arg e "claude exit $rc, no review.md" '.status="failed"|.error=$e' "$out/status.json" > "$out/.s" && mv "$out/.s" "$out/status.json"
fi
git -C "$TASTE_DIR" add reviews model >/dev/null 2>&1 && git -C "$TASTE_DIR" commit -qm "review: $ref ${sha:0:7}" >/dev/null 2>&1
jq -r '"\(.repo)#\(.number) \(.status) \(.questions // 0) questions"' "$out/status.json"
