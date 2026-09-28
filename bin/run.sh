#!/usr/bin/env bash
# usage: run.sh owner/repo#N [owner/repo#M ...]  — several PRs = one set, one review, one dashboard entry
set -u
TASTE_DIR=${TASTE_DIR:-$HOME/.taste}
PLUGIN=$(cd "$(dirname "$0")/.." && pwd)
key=$(printf '%s\n' "$@" | sort | tr '/#' '_-' | paste -sd+ -)
if [ $# = 1 ]; then out=$TASTE_DIR/reviews/${1%#*}/${1#*#}; wd=$TASTE_DIR/repos/${1%#*}
else out=$TASTE_DIR/reviews/_sets/$key; wd=$TASTE_DIR/repos; fi
mkdir -p "$out" "$TASTE_DIR/logs"
rm -rf "$out/review.md" "$out/comment.md" "$out/comments" "$out/flow.excalidraw" "$out/flow.png"
[ -d "$TASTE_DIR/.git" ] || git -C "$TASTE_DIR" init -q
dup=$(printf '%s\n' "$@" | cut -d'#' -f1 | sort | uniq -d)
[ -z "$dup" ] || { echo "two PRs from $dup in one set: one checkout per repo"; exit 1; }

prs='{}'
for ref; do
  meta=$(gh pr view "${ref#*#}" --repo "${ref%#*}" --json title,headRefOid,baseRefName,author,url) || { echo "gh failed for $ref"; exit 1; }
  prs=$(jq --arg r "$ref" --argjson m "$meta" '.[$r]={repo:($r|split("#")[0]),number:($r|split("#")[1]|tonumber),sha:$m.headRefOid,base:$m.baseRefName,title:$m.title,author:$m.author.login,url:$m.url}' <<<"$prs")
done
t=$(date -u +%FT%TZ)
if [ $# = 1 ]; then jq --arg t "$t" 'first(.[])+{status:"running",started:$t}' <<<"$prs"
else jq --arg k "$key" --arg t "$t" '{set:$k,title:first(.[].title),prs:.,status:"running",started:$t}' <<<"$prs"; fi > "$out/status.json"

fail() { jq --arg e "$1" '.status="failed"|.error=$e' "$out/status.json" > "$out/.s" && mv "$out/.s" "$out/status.json"; echo "$* failed: $1"; exit 1; }

for ref; do
  repo=${ref%#*}; n=${ref#*#}; w=$TASTE_DIR/repos/$repo
  sha=$(jq -r --arg r "$ref" '.[$r].sha' <<<"$prs"); base=$(jq -r --arg r "$ref" '.[$r].base' <<<"$prs")
  mkdir -p "$w" "$TASTE_DIR/model/${repo%/*}"
  [ -d "$w/.git" ] || gh repo clone "$repo" "$w" -- -q || fail "clone $repo failed"
  git -C "$w" checkout -q --detach 2>/dev/null
  git -C "$w" fetch -qf origin "$base:refs/remotes/origin/$base" "pull/$n/head" || fail "fetch $ref failed"
  git -C "$w" reset -q --hard "$sha" || fail "sha $sha not in $repo checkout"
  git -C "$w" clean -qfd
  [ "$(git -C "$w" rev-parse HEAD)" = "$sha" ] || fail "$repo checkout is not at $sha"
done

cd "$wd" && TASTE_DIR=$TASTE_DIR TASTE_OUT=$out claude -p "/taste-reviewer:taste-review $*" \
  --plugin-dir "$PLUGIN" --settings '{"enabledPlugins":{"taste-reviewer@taste-reviewer":false}}' --permission-mode bypassPermissions \
  --output-format stream-json --verbose > "$TASTE_DIR/logs/$key-${sha:0:7}.jsonl" 2>&1
rc=$?

if [ ! -s "$out/review.md" ] || [ "$(jq -r .status "$out/status.json")" = running ]; then
  jq --arg e "claude exit $rc, no review.md" '.status="failed"|.error=$e' "$out/status.json" > "$out/.s" && mv "$out/.s" "$out/status.json"
fi
git -C "$TASTE_DIR" add reviews model >/dev/null 2>&1 && git -C "$TASTE_DIR" commit -qm "review: $* ${sha:0:7}" >/dev/null 2>&1
jq -r '"\(.set // "\(.repo)#\(.number)") \(.status) \(.questions // 0) questions"' "$out/status.json"
