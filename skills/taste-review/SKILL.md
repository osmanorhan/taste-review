---
name: taste-review
description: Staff-level taste review of one PR. Input "owner/repo#N". Writes review.md + flow.excalidraw + flow.png + status.json under $TASTE_DIR/reviews/owner/repo/N. Not a line-by-line review. Moving parts, complexity, slop, schema and architecture changes only.
---

Input: `$ARGUMENTS` = `owner/repo#N`. `TASTE_DIR` defaults to `~/.taste`.
Working dir is already the PR checkout (`$TASTE_DIR/repos/owner/repo`, branch `pr-N`, base fetched as `origin/<base>`).
`OUT=$TASTE_DIR/reviews/owner/repo/N`. It exists and holds `status.json`.

## 1. Persona
Read `$TASTE_DIR/persona.md`. It defines who is reviewing: name, stance, what they never comment on.
Every review must carry this persona. Same PR, different persona file = different review.

## 2. Facts
```bash
gh pr view N --repo owner/repo --json title,body,baseRefName,headRefOid,changedFiles,additions,deletions,author,url
git diff --stat origin/<base>...HEAD
git diff --name-only origin/<base>...HEAD
```
Read the changed files whole. Do not trust the PR body or ticket text as fact.
Flag early: any file under migrations/, schema/, *.sql, *.proto, openapi/*, contracts/, or a changed exported type = **schema/architecture change**. Those get the deepest read.

## 3. Lenses (run in parallel with the Agent tool)
- `taste-reviewer:architect` — prompt: "Review branch HEAD vs origin/<base> in this repo. PR owner/repo#N. Return your normal output."
- `taste-reviewer:reliability` — prompt: "Scope: git diff origin/<base>...HEAD. Return your normal output."
- Bash, not an agent:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/complexity/complexity.sh origin/<base>
bash ${CLAUDE_PLUGIN_ROOT}/skills/complexity/drift.sh origin/<base>
bash ${CLAUDE_PLUGIN_ROOT}/skills/complexity/crap.sh origin/<base>
```
If a script fails, note it in "Not measured" and continue.

## 4. Synthesize → `$OUT/review.md`
Merge the three lenses through the persona. Keep only findings a staff reviewer would block or ask about.

```
# owner/repo#N — <title>
**Verdict:** ship | fix first | wrong problem
**Reviewer:** <persona name> — <one-line stance>
**What moved:** <1-2 plain sentences: which parts changed, which new edges appeared>

![flow](flow.png)

## Items
- `file:line` — <what is wrong> — <why, one sentence>. **block**
- `file:line` — <what> — <why>. **ask**

## Schema / architecture change          (only when present)
- <what changed> — <who else reads it> — <what breaks if they disagree>

## Metrics                               (only CRAP > 30 or CCN over threshold, exactly as printed)
## Not measured
- <script or check that could not run, and what would settle it>
```

Rules:
- Max 7 items, each under 40 words. If more, keep the 7 with the highest blast radius.
- Drop: style, naming, formatting, "consider extracting", anything found only because a number was high, anything the persona says it never comments on.
- Every item needs a concrete failing case. No case, no item.
- Slop, heuristics, fallbacks, retries, swallowed errors, monkeypatches nobody asked for: always an item.
- Missing test for a new branch or new contract: an item. Missing test for a rename: not an item.
- Plain short sentences. Reader's English is a second language.

## 5. Diagram → `$OUT/flow.excalidraw` + `$OUT/flow.png`
Follow `taste-reviewer:excalidraw-diagram` (read its SKILL.md and `references/color-palette.md`).
One diagram: **what moved**. Components the PR touched, new edges, removed edges, external readers of any changed contract.
- Touched components: Start/Trigger colors. New edges: Primary. Removed: Warning, dashed. Untouched neighbors that still read the contract: Inactive, dashed.
- Items from section 4 that are **block**: a small Error-colored dot next to the component, with the item number as label.
- 6 to 15 elements with text. No more. Free-floating text over boxes.
Render:
```bash
cd ${CLAUDE_PLUGIN_ROOT}/skills/excalidraw-diagram/references && uv run python render_excalidraw.py $OUT/flow.excalidraw --output $OUT/flow.png
```
Read the PNG once. Fix overlaps or clipped text. Render again. Stop after the second render.

## 6. Finish
Update `$OUT/status.json`: set `"status":"done"`, `"verdict"`, `"items"` (count), `"blocking"` (count), `"ended"` (ISO now). Keep other fields.
If anything above made review.md impossible, set `"status":"failed"` and `"error"`.
Print the verdict line and stop.
