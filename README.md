# taste-reviewer
Async staff-level taste review for PRs where your review is requested. One PR, or several PRs across repos as one change. Not a linter. Moving parts, complexity, slop, schema changes. Short items, one excalidraw diagram, local dashboard, manual approve before posting.

```
GitHub --weekdays 09,12,15,18--> bin/watch.sh --> bin/run.sh --> claude -p /taste-reviewer:taste-review owner/repo#N [owner/repo#M ...]
                                                                  agents: architect ∥ reliability per area ∥ complexity+CRAP
                                                                  → one PR: ~/.taste/reviews/owner/repo/N/
                                                                  → set:    ~/.taste/reviews/_sets/<key>/  (+ comments/owner/repo/N.md)
bin/dashboard.py :7331  → list, view, Approve → gh pr comment (one per PR), Re-run
```

## Mental model
One file per repo: `~/.taste/model/owner/repo.md`. Rewritten in place, never copied. History = `git log` in `~/.taste`.
- every review reads it first and updates it after
- `bin/learn.sh owner/repo#N` (watch runs it when human comments appear) merges other reviewers' comments into it
- `/taste-reviewer:model owner/repo <text>` in any Claude session: talk about the repo or a review; the file updates when a belief changes

## Install
```bash
git clone git@github.com:osmanorhan/taste-review.git ~/work/taste-reviewer && ~/work/taste-reviewer/install.sh
```
Needs `claude`, `gh` (logged in), `jq`, `uv`, `git`, `python3`. Safe to re-run.

It installs the diagram renderer, creates `~/.taste`, loads two launchd jobs, and installs the plugin.
Reviews run weekdays at 09, 12, 15 and 18. The dashboard starts at login on port 7331.

Then edit `~/.taste/persona.md` — that file is who is reviewing. Two people with different personas get different reviews of the same PR.

## Run
One PR now: `bin/run.sh owner/repo#N`

## Sets: several PRs as one change
`bin/run.sh owner/a#1 owner/b#2`
- One review, one dashboard entry. `review.md` holds the whole change. It is only for you.
- The review looks at where the repos meet: contracts changed on one side only, deploy order, the same rule in two repos.
- Each question has a **PR:** line: the PR where the fix goes. On approve, each PR gets only its own questions. `PR: none` questions stay in the review.
- watch.sh does not review a set member alone. It re-runs the whole set when any member gets a new commit.
- Each repo keeps its own model. Learning still runs per PR.
- Limit: one PR per repo in a set.

Env: `TASTE_DIR` (default `~/.taste`), `TASTE_PORT` (7331).
