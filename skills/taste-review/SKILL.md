---
name: taste-review
description: Staff-level taste review of one PR. Input "owner/repo#N". Writes review.md + flow.excalidraw + flow.png + status.json under $TASTE_DIR/reviews/owner/repo/N. Not a line-by-line review. Moving parts, complexity, slop, schema and architecture changes only.
---

Input: `$ARGUMENTS` = `owner/repo#N`. `TASTE_DIR` defaults to `~/.taste`.
Working dir is already the PR checkout (`$TASTE_DIR/repos/owner/repo`, branch `pr-N`, base fetched as `origin/<base>`).
`OUT=$TASTE_DIR/reviews/owner/repo/N`. It exists and holds `status.json`.

## 0. Mental model
Read `$TASTE_DIR/model/owner/repo.md`. If it does not exist, run `taste-reviewer:model bootstrap owner/repo` first (see that skill). The model is the reviewer's memory of the repo. Every judgment below is made against it: does this PR fit the moving parts, does it change a contract, does it contradict a decision.

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

## 4. Write `$OUT/review.md`
You are not hunting bugs. You are building understanding. First write what you understand the change does. Then every place where the code does not match that understanding is a gap. Gaps are the review.

```
# owner/repo#N — <title>
Verdict: ship | fix first | wrong problem
Reviewer: <persona name>

## What this change does
<3-6 short lines. Plain English, like explaining to a smart friend who is not a native speaker.
Name things the way a person talks: "the update method in CampaignController", "the summarize function in the CI script".
Never write file paths or line numbers here.>

## Where it sits
<1-2 lines: which moving part or contract in the mental model this touches, or "new part: X".>

![flow](flow.png)

## Gaps
1. <What I expected> but <what the code does>. <One line: why this matters or what I need to know.>
2. ...

## I could not check
- <one line each, only if it changes the verdict>
```

Rules for gaps:
- A gap is a question or a mismatch, written as a person would say it out loud. Example: "The update method retries three times. A bad input fails the same way three times. What is the retry for?"
- Say the class and method by name in words. No `file:line`, no code blocks, no backticks around whole paths.
- One gap = max three short sentences. Max 7 gaps. Drop the weakest first.
- Say "blocks" at the end of a gap only when the change should not merge with it open.
- Drop: style, naming, formatting, "consider extracting", anything the persona never comments on, anything found only because a number was high.
- A number from the scripts goes inside a gap as words ("the summarize function has 14 branches and no test") only when it explains the gap. Never a separate metrics section.
- Slop, heuristics, fallbacks, retries, swallowed errors, monkeypatches nobody asked for: a gap, because they hide a why.
- A new branch or new contract with no test: a gap. A rename with no test: not a gap.
- No praise, no filler, no summary at the end.

## 5. Diagram → `$OUT/flow.excalidraw` + `$OUT/flow.png`
Follow `taste-reviewer:excalidraw-diagram` (read its SKILL.md and `references/color-palette.md`).
One diagram: **what moved**. Components the PR touched, new edges, removed edges, external readers of any changed contract.
- Touched components: Start/Trigger colors. New edges: Primary. Removed: Warning, dashed. Untouched neighbors that still read the contract: Inactive, dashed.
- Gaps that block: a small Error-colored dot next to the component, with the gap number as label.
- 6 to 15 elements with text. No more. Free-floating text over boxes.
Render:
```bash
cd ${CLAUDE_PLUGIN_ROOT}/skills/excalidraw-diagram/references && uv run python render_excalidraw.py $OUT/flow.excalidraw --output $OUT/flow.png
```
Read the PNG once. Fix overlaps or clipped text. Render again. Stop after the second render.

## 6. Update the mental model
Rewrite `$TASTE_DIR/model/owner/repo.md` in place (rules in `taste-reviewer:model`): new or changed moving parts, contracts, a Decisions line for this PR if it makes one, Risks if a block item stays open. Do not append a log. Commit:
```bash
cd $TASTE_DIR && git add model && git commit -qm "model: owner/repo — PR #N <one line>"
```

## 7. Finish
Update `$OUT/status.json`: set `"status":"done"`, `"verdict"`, `"gaps"` (count), `"blocking"` (count of gaps marked blocks), `"ended"` (ISO now). Keep other fields.
If anything above made review.md impossible, set `"status":"failed"` and `"error"`.
Print the verdict line and stop.
