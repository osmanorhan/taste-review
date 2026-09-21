# taste-reviewer
Async staff-level taste review for PRs where your review is requested. Not a linter. Moving parts, complexity, slop, schema changes. Short items, one excalidraw diagram, local dashboard, manual approve before posting.

```
GitHub --poll 10m--> bin/watch.sh --> bin/run.sh --> claude -p /taste-reviewer:taste-review owner/repo#N
                                                       agents: architect ∥ reliability ∥ complexity+CRAP
                                                       → ~/.taste/reviews/owner/repo/N/{status.json,review.md,flow.excalidraw,flow.png}
bin/dashboard.py :7331  → list, view, Approve → gh pr comment, Re-run
```

## Setup
```bash
cd skills/excalidraw-diagram/references && uv sync && uv run playwright install chromium
cp launchd/*.plist ~/Library/LaunchAgents/ && for f in launchd/*.plist; do launchctl load ~/Library/LaunchAgents/$(basename $f); done
edit ~/.taste/persona.md   # who is reviewing
```
Manual: `bin/run.sh owner/repo#N` then open http://127.0.0.1:7331

Env: `TASTE_DIR` (default `~/.taste`), `TASTE_PORT` (7331).
