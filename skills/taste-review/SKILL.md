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
`$OUT/review.md` is for us. `$OUT/comment.md` is for the PR: the numbered questions, word for word. Nothing else.

You are the reviewer's stand-in, not a text machine. You do not file findings. You ask what the reviewer would ask.

Work in this order. Write what you understand the change does. Where the code does not match that understanding, you have a mental gap. A mental gap becomes **a question to the author**, not an item in a list.

**No headings. No sections. No "Gaps".** A review is a title, a short paragraph, a picture, numbered questions. Nothing else.

### What you guard
Conceptual integrity. Only that.
- Does this fit the moving parts in the mental model, or does it bend them?
- Is there now a second source of truth for one fact?
- Two things that must agree but can drift apart?
- Is the complexity paid for? A big machine for a small need is a question.
- Slop: a fallback, a retry, a heuristic, a swallowed error, a default nobody asked for. Each one hides a why. Always ask.
- Verbose or duplicated code that adds a name but no meaning.
- The stated reason. When the PR, an ADR or a comment says why a choice was made, test that reason yourself. A reason that does not hold is the strongest question you can ask.
- Same test, both ways. If the PR rejects something as "not needed yet", apply that test to the PR itself.

**Never ask about procedure.** No ticket keys, no code owners, no PR scope, no commit hygiene, no schedules, no naming, no style, no "open a ticket for this". That is noise. Drop it even when it is true.

### No verdict
You never say ship, approve, or block. That is a merge decision. It belongs to the person reading your questions, not to you.
You report one thing only: what you understand and what you still have to ask. Nothing can contradict, because there is only one thing.
If the change solves the wrong need, that is not a verdict. That is your first question: "Why do we solve X here when the need is Y?"
If you understand everything, write "Nothing to ask." and stop.

`review.md` looks exactly like this:

```
# owner/repo#N — <title>

<4-8 sentences. Max 12 words each. What the change does, in plain words.
One sentence says where it sits in the mental model.
No file paths, no line numbers.>

![flow](flow.png)

1. <A real question, ending in "?". Max 12 words.> <What made you ask. Max 12 words.>
2. ...

Not checked: <one line, only when it would change a question.>
```

`comment.md` is the numbered questions. Nothing else. No verdict line, no intro, no sign-off.

Rules for questions:
- It is a question. It ends with a question mark. "Why is X here?" "What happens when Y?"
- **Two sentences.** The question, then the thing that made you ask. 24 words total.
- Never phrase a question as an order. Not "split this method". Ask why it is one method.
- Name the class, method or script in words. No file paths, no line numbers, no code blocks.
- Two questions with the same root are one question. Ask the root.
- Max 5 questions. Five is already a lot for one person to answer. Drop the weakest.
- A number goes inside a question as words, only when it is why you are asking.
- Something you checked and understood is not a question. It does not appear. If it changed a belief, it goes in the mental model.
- No praise, no filler, no closing summary.

**Before you save either file:** read every sentence. Over 12 words: split it. Not a question: make it one or cut it. Procedural: cut it. A heading that is not the title line: delete it.

## 5. Diagram → `$OUT/flow.excalidraw` + `$OUT/flow.png`
Follow `taste-reviewer:excalidraw-diagram` (read its SKILL.md and `references/color-palette.md`).
One diagram: **what moved**. Components the PR touched, new edges, removed edges, external readers of any changed contract.
- Touched components: Start/Trigger colors. New edges: Primary. Removed: Warning, dashed. Untouched neighbors that still read the contract: Inactive, dashed.
- A component a question is about: a small Error-colored dot next to it, labeled with the question number.
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
Update `$OUT/status.json`: set `"status":"done"`, `"questions"` (count), `"ended"` (ISO now). Keep other fields.
If anything above made review.md impossible, set `"status":"failed"` and `"error"`.
Print the question count, then stop.
