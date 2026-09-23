#!/usr/bin/env bash
# Install taste-reviewer for the current user. Safe to re-run.
set -eu
P=$(cd "$(dirname "$0")" && pwd)
TASTE_DIR=${TASTE_DIR:-$HOME/.taste}
LA=$HOME/Library/LaunchAgents

for c in claude gh jq uv git python3; do
  command -v $c >/dev/null || { echo "missing: $c"; exit 1; }
done
gh auth status >/dev/null 2>&1 || { echo "run: gh auth login"; exit 1; }

echo "1/4 diagram renderer"
(cd "$P/skills/excalidraw-diagram/references" && uv sync -q && uv run playwright install -q chromium 2>/dev/null) || true

echo "2/4 state dir $TASTE_DIR"
mkdir -p "$TASTE_DIR"/{reviews,repos,logs,model}
[ -d "$TASTE_DIR/.git" ] || git -C "$TASTE_DIR" init -q
[ -f "$TASTE_DIR/.gitignore" ] || printf 'repos/\nlogs/\nlock/\n' > "$TASTE_DIR/.gitignore"
[ -f "$TASTE_DIR/persona.md" ] || cp "$P/persona.example.md" "$TASTE_DIR/persona.md"

echo "3/4 background jobs"
mkdir -p "$LA"
PATHS="$(dirname "$(command -v claude)"):$(dirname "$(command -v gh)"):$(dirname "$(command -v uv)"):/usr/bin:/bin"
job() {
  cat > "$LA/$1.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$1</string>
<key>ProgramArguments</key><array>$2</array>
$3
<key>StandardOutPath</key><string>$TASTE_DIR/logs/$1.log</string>
<key>StandardErrorPath</key><string>$TASTE_DIR/logs/$1.log</string>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>$PATHS</string><key>TASTE_DIR</key><string>$TASTE_DIR</string></dict>
</dict></plist>
EOF
  launchctl unload "$LA/$1.plist" 2>/dev/null || true
  launchctl load "$LA/$1.plist"
}
# weekdays, every 3 hours, 09:00-18:00
slots=""
for h in 9 12 15 18; do for d in 1 2 3 4 5; do
  slots="$slots<dict><key>Weekday</key><integer>$d</integer><key>Hour</key><integer>$h</integer><key>Minute</key><integer>0</integer></dict>"
done; done
job com.taste.watch "<string>$P/bin/watch.sh</string>" "<key>StartCalendarInterval</key><array>$slots</array>"
job com.taste.dashboard "<string>$(command -v python3)</string><string>$P/bin/dashboard.py</string>" "<key>KeepAlive</key><true/>"

echo "4/4 plugin"
claude plugin marketplace add "$P" 2>/dev/null || true
claude plugin install taste-reviewer@taste-reviewer 2>/dev/null || echo "  install by hand: claude plugin install taste-reviewer@taste-reviewer"

echo
echo "done. dashboard: http://127.0.0.1:${TASTE_PORT:-7331}"
echo "reviews run weekdays at 09, 12, 15, 18."
echo "edit who is reviewing: $TASTE_DIR/persona.md"
echo "one PR now: $P/bin/run.sh owner/repo#N"
