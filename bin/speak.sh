#!/usr/bin/env bash
# usage: speak.sh <review dir> — story.tr.md → story.m4a with VoxCPM2, else macOS Yelda. story.voice says which.
set -u
d=$1
rm -f "$d/story.m4a" "$d/story.voice"
if "$(dirname "$0")/speak.py" "$d/story.tr.md" "$d/.story.wav" "${TASTE_DIR:-$HOME/.taste}/voices" > "$d/.speak.log" 2>&1; then
  src=$d/.story.wav; voice=VoxCPM2
elif say -v Yelda -f "$d/story.tr.md" -o "$d/.story.aiff" >> "$d/.speak.log" 2>&1; then
  src=$d/.story.aiff; voice="Yelda: VoxCPM2 failed, see .speak.log"
else
  echo "failed: see .speak.log" > "$d/story.voice"; exit 1
fi
afconvert -f m4af -d aac "$src" "$d/story.m4a" >> "$d/.speak.log" 2>&1 || { echo "failed: afconvert, see .speak.log" > "$d/story.voice"; exit 1; }
rm -f "$src"
echo "$voice" > "$d/story.voice"
