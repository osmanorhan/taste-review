---
name: taste-review
description: Staff-level taste review of one PR. Input "owner/repo#N". Writes review.md + flow.excalidraw + flow.png + status.json under $TASTE_DIR/reviews/owner/repo/N. Not a line-by-line review. Moving parts, complexity, slop, schema and architecture changes only.
---

Input: `$ARGUMENTS` = `owner/repo#N`. `TASTE_DIR` defaults to `~/.taste`.
Working dir is already the PR checkout (`$TASTE_DIR/repos/owner/repo`, detached at the PR head sha, base as `origin/<base>`).
`OUT=$TASTE_DIR/reviews/owner/repo/N`. It exists and holds `status.json`.

## Sentence rule (applies to every word this skill writes)
The reader has ADHD. English is their second language. A long sentence is not read, it is skipped.

- **Max 12 words per sentence.** Count them.
- One idea per sentence. If a sentence has two ideas, make two sentences.
- No clause joining: no "which", "that used to", "plus", "while", "so that", no semicolons, no dashes holding a second thought.
- No participle chains ("rewritten as ... , buried inside ...").
- Plain words. "runs" not "is executed". "now" not "as of this change".
- Never pack a number and an explanation into one sentence. Split them.

Bad:
> Fifty wire checks that used to run against staging from the automation repo are rewritten as Java test classes inside this service, plus about ninety more that were buried inside the staging flows.

Good:
> Fifty wire checks used to run on staging. They lived in the automation repo. Now they are Java tests in this service. Ninety more came out of the staging flows.

## 0. Mental model
Read `$TASTE_DIR/model/owner/repo.md`. If it does not exist, run `taste-reviewer:model bootstrap owner/repo` first (see that skill). The model is the reviewer's memory of the repo. Every judgment below is made against it: does this PR fit the moving parts, does it change a contract, does it contradict a decision.

## 1. Persona
Read `$TASTE_DIR/persona.md`. It defines who is reviewing: name, stance, what they never comment on.
The persona steers judgment. It is never written into the output. No name, no stance line, no self-description.

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

## 4. Write two files
`$OUT/review.md` is for us. `$OUT/comment.md` is for the PR: the verdict word and the numbered gaps, copied word for word. Nothing else.

You are not hunting bugs. You are building understanding. Write what you understand. Every place the code does not match it is a gap. Gaps are the review.

**No headings. No sections. No chapters.** A review is a title, a verdict, a short paragraph, a picture, a numbered list. That is all. A traditional code review with six headings is the thing we are replacing.

`review.md` looks exactly like this:

```
# owner/repo#N — <title>
ship | fix first | wrong problem

<4-8 sentences. Max 12 words each. What the change does, in plain words.
One of these sentences says where it sits in the mental model.
No file paths, no line numbers.>

![flow](flow.png)

1. <The mismatch. Max 12 words.> <The case where it hurts. Max 12 words.> [blocks]
2. ...

Not checked: <one line, only when it could change the verdict.>
```

`comment.md` is the verdict word, a blank line, then the numbered list. Nothing else.

Rules for gaps:
- A gap is a mismatch between what you understood and what the code does. Say it out loud like a person.
- **Two sentences. Hard limit.** First: the mismatch. Second: the case where it hurts. Need a third? It is two gaps, or you do not understand it yet.
- 24 words per gap, total. Obey the sentence rule above.
- Name the class, method or script in words. No file paths, no line numbers, no code blocks.
- Max 7 gaps. Drop the weakest first.
- Add `[blocks]` at the end only when the change should not merge with this open.
- Drop: style, naming, formatting, "consider extracting", anything the persona never comments on, anything found only because a number was high.
- A number goes inside a gap as words, only when it explains the gap.
- Fallbacks, retries, heuristics, swallowed errors, monkeypatches nobody asked for: a gap. They hide a why.
- A new branch or new contract with no test: a gap. A rename with no test: not a gap.
- Something you checked and cleared is not a gap. It is not in the review either. If it changed a belief, it goes in the mental model.
- No praise, no filler, no closing summary.

**Before you save either file:** read every sentence. Over 12 words: split it. A comma holding two ideas: split it. A heading that is not the title line: delete it.

## 5. Diagram → `$OUT/flow.excalidraw` + `$OUT/flow.png`
Follow `taste-reviewer:excalidraw-diagram` (read its SKILL.md and `references/color-palette.md`).
One diagram: **what moved**. Components the PR touched, new edges, removed edges, external readers of any changed contract.
- Touched components: Start/Trigger colors. New edges: Primary. Removed: Warning, dashed. Untouched neighbors that still read the contract: Inactive, dashed.
- Gaps marked [blocks]: a small Error-colored dot next to the component, with the gap number as label.
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
