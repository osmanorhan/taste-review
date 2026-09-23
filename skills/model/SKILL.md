---
name: model
description: The mental model of one repo. One file, rewritten in place, never versioned as separate docs. Modes - "owner/repo" shows it, "owner/repo <text>" discusses and updates it, "learn owner/repo#N" merges other reviewers' PR comments into it, "bootstrap owner/repo" builds it from the code.
---

`TASTE_DIR` defaults to `~/.taste`. Model file: `$TASTE_DIR/model/owner/repo.md`. Checkout: `$TASTE_DIR/repos/owner/repo`.

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

## The one rule
There is exactly one mental model per repo. You edit that file. You never create a second file, a dated copy, a "v2", a summary, or a per-PR model. History lives in git (`$TASTE_DIR` is a git repo), not in files.
Rewrite sections, do not append logs. A model is a current belief, not a diary. When a belief changes, replace it and put the reason in **Decisions** with the date and the PR.

## Format (keep these sections, keep them short)
```
# owner/repo — mental model
_updated YYYY-MM-DD from PR #N_

## Purpose
One paragraph. What the repo is for, who calls it, what it must never break.

## Moving parts
- <part> — <what it does> — <talks to: part, part>
(only parts that matter for a review; 5–15 lines)

## Boundaries
- <layer or bounded context> — <what it owns> — <may depend on: X> — <must never depend on: Y>
(read from the code: packages, imports, ports. Not from docs.)

## Contracts
- <schema / API / event / config> — <who writes it> — <who reads it> — <what breaks if it changes>

## Decisions
- YYYY-MM-DD PR #N — <decision> — <why>
(newest first, max 20; drop the oldest that no longer shapes the code)

## Risks
- <where it breaks later> — <why we believe that>

## Review lessons
- <what human reviewers caught that we missed, or what we flagged that they ignored> — <rule we take from it>
(max 10, replace weak ones)

## Open questions
- <thing nobody could settle> — <what would settle it>
```

## Modes

### `owner/repo`
Print the file. If missing, say so and run bootstrap.

### `bootstrap owner/repo`
Read the checkout: entrypoints, module tree, migrations/schema, CI, top-level configs. Write the file from code only. Do not read README or docs as fact; read them last, only to fill Purpose, and mark them "from docs, unverified".

### `learn owner/repo#N`
```bash
gh api repos/owner/repo/pulls/N/comments --paginate -q '.[] | {user:.user.login, path, line, body}'
gh api repos/owner/repo/pulls/N/reviews  --paginate -q '.[] | {user:.user.login, state, body}'
gh pr view N --repo owner/repo --json state,mergedAt,title
```
Compare with `$TASTE_DIR/reviews/owner/repo/N/review.md`.
- Human caught, we missed → **Review lessons** + maybe **Risks**.
- We flagged, author or humans pushed back with a reason → **Decisions** (the reason), and a lesson if our flag was wrong.
- PR merged → any contract or moving part it changed goes into **Contracts** / **Moving parts**.
Skip bot comments and pure style threads.

### `owner/repo <free text>`
The reviewer is talking to you about the repo or about a review. Answer from the model and the code, short. If the talk changes a belief (a part, a contract, a decision, a risk), update the file in the same turn and say which section changed. If it does not, change nothing and say so.

## After every write
```bash
cd $TASTE_DIR && git add model && git commit -qm "model: owner/repo — <one line what changed>"
```
End with one line: which sections changed.
