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
- B1 English. Use words a learner knows. "code path" not "tail". "user" not "actor". "reason" not "rationale". Code names stay as they are.
- Never pack a number and an explanation into one sentence. Split them.

Bad:
> Fifty wire checks that used to run against staging from the automation repo are rewritten as Java test classes inside this service, plus about ninety more that were buried inside the staging flows.

Good:
> Fifty wire checks used to run on staging. They lived in the automation repo. Now they are Java tests in this service. Ninety more came out of the staging flows.

## 0. Mental model
Read `$TASTE_DIR/model/owner/repo.md`. If it does not exist, run `taste-reviewer:model bootstrap owner/repo` first (see that skill).
Then read the format: `cat ${CLAUDE_PLUGIN_ROOT}/skills/model/SKILL.md`. Compare its `##` sections with the model file. If one is missing, fill it now from the code on `origin/<base>`, before you look at the PR.
For Boundaries, the repo's own convention docs (`.claude/rules/`, `CLAUDE.md`, `CONTRIBUTING`, `docs/adr/`) are a map, not the truth. Keep a convention only when the code confirms it: count how many places follow it. Write the count next to it. Commit it on its own: `model: owner/repo — fill <section>`. The model is the reviewer's memory of the repo. Every judgment below is made against it: does this PR fit the moving parts, does it change a contract, does it contradict a decision.

If this PR was reviewed before at another commit, read that review: `git -C $TASTE_DIR show HEAD:reviews/owner/repo/N/review.md` (run.sh deletes the working copy before each run, so read it from git). For each old question, check the new code. Fixed: do not ask it again. Not fixed: ask it again. Then review the rest with fresh eyes. Old questions are not a limit on what you look at.

## 1. Persona
Read `$TASTE_DIR/persona.md`. It defines who is reviewing: name, stance, what they never comment on.
The persona steers judgment. It is never written into the output. No name, no stance line, no self-description.

## 2. Facts
```bash
gh pr view N --repo owner/repo --json title,body,baseRefName,headRefOid,changedFiles,additions,deletions,author,url
git diff --stat origin/<base>...HEAD
git diff --name-only origin/<base>...HEAD
```
Read the changed files whole.
Read the PR body and the commit messages to learn what the PR says it solves and what it already explains. Verify each claim in the code. A claim the code does not back is not a fact.
Flag early: any file under migrations/, schema/, *.sql, *.proto, openapi/*, contracts/, or a changed exported type = **schema/architecture change**. Those get the deepest read.

## 3. Map the change, then send the lenses
Do what a human reviewer does first. List every changed file that is not a test. Group them into areas by what they do together: one feature, one flow, one adapter family, config. Use 1 area for a small PR and at most 6 for a big one. Every file belongs to exactly one area. Keep this map to yourself. It is never written into the review.

Then start these agents in one message, so they run in parallel:
- `taste-reviewer:architect`, once, on the whole change — prompt: "Review branch HEAD vs origin/<base> in this repo. PR owner/repo#N. Focus on how the areas work together. Return your normal output."
- `taste-reviewer:reliability`, once per area — prompt: "Scope: git diff origin/<base>...HEAD -- <the area's files>. Read every one of these files in full. Return your normal output."
- Metrics, with Bash, not an agent. First make a coverage report with the repo's own test task. Examples: Gradle `./gradlew test jacocoTestReport`, npm `npx jest --coverage`, Go `go test -coverprofile=coverage.out ./...`, PHP `vendor/bin/phpunit --coverage-clover clover.xml`. Use what the repo already has. If it has no coverage tool, run one just for this review without changing any file the repo tracks: Python `uv run --with pytest-cov pytest --cov=<src> --cov-report=lcov:coverage/lcov.info`, Node `npx --yes c8 --reporter=lcov npm test`. Never edit dependency files. If tests need a database or network you do not have, skip coverage and say why.
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/complexity/complexity.sh origin/<base>
bash ${CLAUDE_PLUGIN_ROOT}/skills/complexity/drift.sh origin/<base>
bash ${CLAUDE_PLUGIN_ROOT}/skills/complexity/crap.sh origin/<base> [report-path]
```
If a script fails, record why in the metrics (step 7) and continue.

## 4. Read it as one whole, then write two files
`$OUT/review.md` is for us. `$OUT/comment.md` is for the PR.

The lenses and metrics feed your understanding. Now read the change yourself, as one piece, against the mental model. While you read, look closely at what the lenses often miss:
- What changed type, range, nullability or format. Follow it to every producer and consumer. Grep the same name across the repo too: one name with two types means two concepts.
- Where each new rule lives. Name its kind by what it does: validates input, authorizes, maps, persists. Compare with where the repo keeps that same kind. A class name states its job. Code of another kind inside it is a second job.
- What each new branch is for. Does it follow a pattern the repo uses elsewhere? Is it reachable, or does another layer already stop it?
- How the flow moved. Walk one request or run from entry to exit, across all areas. Then walk it again with one step failing, for each step. Count how often each changed call runs on that path. Watch for the same steps copied into sibling branches. Copies must change together, and one will drift.
- Every new or changed number: a threshold, limit, timeout, retry count, size or interval. Try the edge values: zero, one, just under, equal, just over. If a library reads the number, check what the library means by it: the unit, and whether it counts retries or total attempts.
- What the new code rebuilds. Does it hand-roll something the language, the framework or an installed dependency already does? Is a new abstraction, config value or layer used by only one caller? First check how the repo does it elsewhere. A hand-written way the code uses on purpose everywhere is a convention, not waste. One small test is never waste.
Read every changed file that is not a test at least once yourself, area by area. The lenses help. They do not replace your own read.
You do not list these. Most of what you look at is fine, and fine things never appear anywhere. You only surface what is wrong.

Surface something only when it changes what the reader must believe about the system:
- It behaves differently than the PR says. This includes a type or format change that a caller was not updated for.
- It can fail quietly. A fallback, default, retry, swallowed error or unreachable guard hides a failure. Complex code with no test (CRAP over 30) counts.
- It breaks the shape of the repo. A rule sits outside the layer where its kind lives. One name means two things. A class takes a second job. A branch is patched in for one case. Steps are copied instead of shared. A convention the code follows everywhere else is broken. Code rebuilds what the platform already gives, or adds a layer with one user.
- Something it depends on is missing.

Nothing else is surfaced. Not taste. Not "could be simpler". Not procedure.
Read everything, then report little. The effort is in the reading, never in the number of questions. Zero questions is a good review, but only after a full read. Two questions with the same root are one question.
A finding from this PR is a question, never a line in the model. The model describes the repo as it is on the base branch, plus what humans have decided. Something this PR introduces is not a belief yet. If you catch yourself writing "this PR is the first to…" or "this PR adds an exception…" into any model section, stop. That is a question. You never say ship or block. That is the reader's call.

`review.md` looks exactly like this:

```
# owner/repo#N — <title>

<3-6 sentences. Max 12 words each. What the change does, in plain words.
One sentence says where it sits in the mental model.>

![flow](flow.png)

<Either: "Nothing to ask."
 Or, per question, this block. Keep the blank lines. They make GitHub show a clean list.>

**1. <The question? Max 12 words.>**

- **Before:** <the exact old value, text or behaviour>
- **Now:** <the exact new one>
- **Risk:** <one sentence: what can go wrong, and who sees it>
- **Fix:** <one sentence: what replaces it. Leave this line out if you do not know.>
```

Write `comment.md` only when there is at least one question. It holds the question blocks and nothing else.

Rules:
- A question ends with "?". Never phrase it as an order.
- Before and Now are exact. Quote the real string, value, status code, log level, or call. Wrap code names in backticks.
- Risk names who is hurt and how. One sentence.
- Fix names the library call, the framework feature, the existing helper, or "delete it".
- No file paths, no line numbers, no code blocks.
- No other headings. No praise, no filler, no summary.
- Do not ask about something the PR already solves or explains. Check the code, the tests and the PR body first. Ask only when the reason given does not hold in the code.

**Before you save:** does each question pass the "surface only when" test? Does the PR already solve or explain it? Then delete it. Is any line more than one sentence? Cut it. Over 12 words: split it.

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
Rewrite `$TASTE_DIR/model/owner/repo.md` in place (rules in `taste-reviewer:model`). Change only beliefs about the base branch that reading this PR showed were wrong or missing. The PR's own changes do not go in. They enter when it merges, through the learn step. If nothing about the base changed, do not touch the model. Do not append a log. Commit:
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
  "read": {"files": 34, "of": 34},
  "drift": ["<one line per hit>"]
}
```
Empty list = measured, nothing over threshold. Missing key = not measured.
If anything above made review.md impossible, set `"status":"failed"` and `"error"`.
Print the question count, then stop.
