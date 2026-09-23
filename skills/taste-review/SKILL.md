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
Read `$TASTE_DIR/model/owner/repo.md`. If it does not exist, run `taste-reviewer:model bootstrap owner/repo` first (see that skill).
Then read the format: `cat ${CLAUDE_PLUGIN_ROOT}/skills/model/SKILL.md`. Compare its `##` sections with the model file. If one is missing, fill it now from the code on `origin/<base>`, before you look at the PR.
For Boundaries, the repo's own convention docs (`.claude/rules/`, `CLAUDE.md`, `CONTRIBUTING`, `docs/adr/`) are a map, not the truth. Keep a convention only when the code confirms it: count how many places follow it. Write the count next to it. The structural pass needs it. Commit it on its own: `model: owner/repo — fill <section>`. The model is the reviewer's memory of the repo. Every judgment below is made against it: does this PR fit the moving parts, does it change a contract, does it contradict a decision.

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
- Metrics, with Bash, not an agent. First make a coverage report with the repo's own test task. Examples: Gradle `./gradlew test jacocoTestReport`, npm `npx jest --coverage`, Go `go test -coverprofile=coverage.out ./...`, PHP `vendor/bin/phpunit --coverage-clover clover.xml`. Use what the repo already has. Never add a tool. If tests need a database or network you do not have, skip coverage and say why.
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/complexity/complexity.sh origin/<base>
bash ${CLAUDE_PLUGIN_ROOT}/skills/complexity/drift.sh origin/<base>
bash ${CLAUDE_PLUGIN_ROOT}/skills/complexity/crap.sh origin/<base> [report-path]
```
If a script fails, record why in the metrics (step 7) and continue.

### Structural pass (you do this yourself, every review, before step 4)
Do not rely on the lenses for these three. Scan the diff directly.
1. **Types.** List every field, parameter, return, column or id whose type, range, nullability or format changed. For each, find its producers and consumers. Check the values that no longer fit.
   Then grep the same name across the whole repo. If the same name carries a different type elsewhere, two concepts share one name. That is a boundary question.
2. **Placement.** List every new check, validation, mapping or policy. Name its kind by what it does: validates client input, authorizes, maps, persists, formats. The sibling is where this repo does that same kind, not where the same data is read.
   A class name states its job. New code in it that does a different kind of job is a second responsibility, whatever data it touches.
   Also check the new code against the verified conventions in Boundaries. Breaking one is a boundary question.
3. **Branches.** List every branch added to an existing if/else, switch or early-return chain. "Fine" must name the established pattern it follows, with one other place that uses it.
   A branch that another layer already prevents is unreachable. Unreachable defensive code is slop, so it is a question.
Most items on these lists are fine. They only become questions through the triggers in step 4.
Write every item into `status.json` under `"pass"` (step 7), with your decision. An item you did not write down was not checked.
For placement, the decision must name the sibling you found and its layer. "Fine" without a sibling is not a decision.
A changed function with CRAP over 30 is complex and untested. That is trigger 3: it can break with nobody noticing.

## 4. Write two files
`$OUT/review.md` is for us. `$OUT/comment.md` is for the PR.

First, help the reviewer learn the change fast. Then ask only what must be asked.

### When to ask
Ask only when one of these is true:
- Behaviour changes and the PR does not say so.
- A type, range or format changes, and a producer or consumer was not updated for it.
- A fallback, default, retry, swallowed error or unreachable guard hides a failure or a why.
- A branch is patched into shared logic to handle one case.
- Production can break and nobody would notice.
- Something the change depends on is missing.
- A boundary breaks. A rule lands outside the layer where rules of its kind already live. New code breaks a convention the code follows everywhere else. One name now means two things. Check the Boundaries in the mental model. Domain knows infra. Logic sits in the wrong layer. One context reaches into another. A class takes a second job. A port or switch grows instead of a new implementation.

Nothing else earns a question. Not taste. Not "could be simpler". Not procedure.
Most PRs have zero or one question. Zero is a good review, not a lazy one. But zero comes after the structural pass, never instead of it.
Never search for questions to fill a list. If you have to look hard, there is nothing.
Two questions with the same root are one question.

The lenses in step 3 find many things. Almost all of them are dropped. They feed your understanding, not the question list.
A finding from this PR that hits a trigger is a question. Never move it into the model's Risks instead. The model holds beliefs about the repo, not questions you did not ask.

### No verdict
You never say ship, approve, or block. That is the reader's decision.

`review.md` looks exactly like this:

```
# owner/repo#N — <title>

<3-6 sentences. Max 12 words each. What the change does, in plain words.
One sentence says where it sits in the mental model.>

![flow](flow.png)

<Either: "Nothing to ask."
 Or, per question:>
1. <The question? Max 12 words.>
   Was: <the exact old value, text or behaviour>. Now: <the exact new one>.
   <1-2 short sentences. The mechanic: who reads it, what happens now, step by step.>
```

Write `comment.md` only when there is at least one question. It holds the numbered questions and nothing else.

Rules:
- A question ends with "?". Never phrase it as an order.
- Was/Now is exact. Quote the real string, value, status code, log level, or call. Never "the message changed".
- The mechanic is concrete. Name the caller and what it does with the value. Example: "The worker matches this text to decide a retry. It will not match now."
- Name things in words. No file paths, no line numbers, no code blocks.
- No headings except the title. No praise, no filler, no summary.

**Before you save:** read each question again. Does it hit one of the four triggers? If not, delete it. Then read each sentence. Over 12 words: split it.

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
Rewrite `$TASTE_DIR/model/owner/repo.md` in place (rules in `taste-reviewer:model`): new or changed moving parts, contracts, a Decisions line for this PR if it makes one, Risks only for things that are not this PR's questions. Do not append a log. Commit:
```bash
cd $TASTE_DIR && git add model && git commit -qm "model: owner/repo — PR #N <one line>"
```

## 7. Finish
Update `$OUT/status.json`: set `"status":"done"`, `"questions"` (count), `"ended"` (ISO now), and `"metrics"`. Keep other fields.
`metrics` holds the numbers exactly as the scripts printed them. Numbers never go in review.md. The dashboard shows them.
```json
"metrics": {
  "coverage": "jacoco, 71% line" | "not measured: <why>",
  "crap": [{"fn": "ClassName.method", "crap": 42, "ccn": 9, "cov": 12}],
  "complexity": [{"fn": "ClassName.method", "ccn": 14, "cog": 18}],
  "drift": ["<one line per hit>"]
}
```
Empty list = measured, nothing over threshold. Missing key = not measured.
`pass` holds the structural pass:
```json
"pass": {
  "types":     [{"what": "<field/param/column>", "was": "<old type>", "now": "<new type>", "same_name_elsewhere": "<types found, with counts>", "decision": "fine: <why> | question <n>"}],
  "placement": [{"what": "<new rule>", "where": "<class>", "kind": "<what the rule does>", "sibling": "<where this repo does the same kind>", "decision": "fine: <why> | question <n>"}],
  "branches":  [{"what": "<added branch>", "where": "<class.method>", "decision": "fine: follows <pattern>, also in <place> | question <n>"}]
}
```
Empty list = scanned, nothing found.
If anything above made review.md impossible, set `"status":"failed"` and `"error"`.
Print the question count, then stop.
