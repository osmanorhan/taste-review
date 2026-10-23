#!/usr/bin/env bash
# usage: speak.sh <review dir> — story.tr.md → story.m4a with VoxCPM2, else macOS Yelda. story.voice says which.
set -u
d=$1
lock=${TASTE_DIR:-$HOME/.taste}/lock-speak
rm -f "$d/story.m4a" "$d/story.voice"
if ! mkdir "$lock" 2>/dev/null; then
  kill -0 "$(cat "$lock/pid" 2>/dev/null)" 2>/dev/null && { echo "busy: another story is being spoken, press again later" > "$d/story.voice"; exit 1; }
  rm -rf "$lock"; mkdir "$lock" || exit 1
fi
echo $$ > "$lock/pid"
trap 'rm -rf "$lock" "$d/.story.src" "$d/.story.wav" "$d/.story.aiff" "$d/.story.m4a"' EXIT
cp "$d/story.tr.md" "$d/.story.src" || exit 1
if "$(dirname "$0")/speak.py" "$d/.story.src" "$d/.story.wav" "${TASTE_DIR:-$HOME/.taste}/voices" > "$d/.speak.log" 2>&1; then
  src=$d/.story.wav; voice=VoxCPM2
elif say -v Yelda -f "$d/.story.src" -o "$d/.story.aiff" >> "$d/.speak.log" 2>&1; then
  src=$d/.story.aiff; voice="Yelda: VoxCPM2 failed, see .speak.log"
else
  echo "failed: see .speak.log" > "$d/story.voice"; exit 1
fi
afconvert -f m4af -d aac "$src" "$d/.story.m4a" >> "$d/.speak.log" 2>&1 || { echo "failed: afconvert, see .speak.log" > "$d/story.voice"; exit 1; }
cmp -s "$d/.story.src" "$d/story.tr.md" || exit 0
mv "$d/.story.m4a" "$d/story.m4a"
echo "$voice" > "$d/story.voice"
