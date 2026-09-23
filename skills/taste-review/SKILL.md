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
For Boundaries, the repo's own convention docs (`.claude/rules/`, `CLAUDE.md`, `CONTRIBUTING`, `docs/adr/`) are a map, not the truth. Keep a convention only when the code confirms it: count how many places follow it. Write the count next to it. Commit it on its own: `model: owner/repo — fill <section>`. The model is the reviewer's memory of the repo. Every judgment below is made against it: does this PR fit the moving parts, does it change a contract, does it contradict a decision.

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

## 4. Read it as one whole, then write two files
`$OUT/review.md` is for us. `$OUT/comment.md` is for the PR.

The lenses and metrics feed your understanding. Now read the change yourself, as one piece, against the mental model. While you read, look closely at what the lenses often miss:
- What changed type, range, nullability or format. Follow it to every producer and consumer. Grep the same name across the repo too: one name with two types means two concepts.
- Where each new rule lives. Name its kind by what it does: validates input, authorizes, maps, persists. Compare with where the repo keeps that same kind. A class name states its job. Code of another kind inside it is a second job.
- What each new branch is for. Does it follow a pattern the repo uses elsewhere? Is it reachable, or does another layer already stop it?
- How the flow moved. Walk one request from entry to exit. Count how often each changed call runs on that path. Watch for the same steps copied into sibling branches. Copies must change together, and one will drift.
- What the new code rebuilds. Does it hand-roll something the language, the framework or an installed dependency already does? Is a new abstraction, config value or layer used by only one caller? First check how the repo does it elsewhere. A hand-written way the code uses on purpose everywhere is a convention, not waste. One small test is never waste.
You do not list these. Most of what you look at is fine, and fine things never appear anywhere. You only surface what is wrong.

Surface something only when it changes what the reader must believe about the system:
- It behaves differently than the PR says. This includes a type or format change that a caller was not updated for.
- It can fail quietly. A fallback, default, retry, swallowed error or unreachable guard hides a failure. Complex code with no test (CRAP over 30) counts.
- It breaks the shape of the repo. A rule sits outside the layer where its kind lives. One name means two things. A class takes a second job. A branch is patched in for one case. Steps are copied instead of shared. A convention the code follows everywhere else is broken. Code rebuilds what the platform already gives, or adds a layer with one user.
- Something it depends on is missing.

Nothing else is surfaced. Not taste. Not "could be simpler". Not procedure.
Most PRs have zero or one question. Zero is a good review. Two questions with the same root are one question.
A finding from this PR is a question, never a line hidden in the model's Risks. You never say ship or block. That is the reader's call.

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
- Was/Now is exact. Quote the real string, value, status code, log level, or call.
- The mechanic names the caller and what it does with the value.
- When the question is about code that should not exist, name what replaces it: the library call, the framework feature, the existing helper, or nothing.
- Name things in words. No file paths, no line numbers, no code blocks.
- No headings except the title. No praise, no filler, no summary.

**Before you save:** does each question pass the "surface only when" test? If not, delete it. Over 12 words: split it.

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
If anything above made review.md impossible, set `"status":"failed"` and `"error"`.
Print the question count, then stop.
