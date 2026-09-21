---
name: complexity
description: >
  Measure cyclomatic and cognitive complexity of the files changed in the current
  branch / PR, and report only functions over threshold. Use when the user says
  "complexity", "cyclomatic", "cognitive complexity", "is this PR too complex",
  "/complexity", or asks for complexity numbers during a code review. Also runs an
  LLM-drift check (commented-out code, unused imports/vars/args, redundant branches,
  comment bloat) when the user says "drift", "slop", "unnecessary code", "too many
  comments", or reviews AI-written code.
---

Run the script from the repo root:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/complexity/complexity.sh [base-ref]
```

- Base ref defaults to the first of `origin/develop`, `origin/main`, `origin/master`.
- Thresholds: `CCN_MAX=10` (cyclomatic), `COG_MAX=15` (cognitive). Override via env:
  `CCN_MAX=15 COG_MAX=20 bash ${CLAUDE_PLUGIN_ROOT}/skills/complexity/complexity.sh`
- Tools run via `uvx`, nothing is installed: `lizard` (cyclomatic, ~15 languages),
  `complexipy` (cognitive, Python files only).

## Reporting

Only report what the script printed. Do not estimate complexity by reading code.

For each function over threshold, one line:
`file:line fn — CCN N / COG M → <the single reason it is high>`

Reason must name the actual structure: nested loop + try, 4-branch if-chain,
flag parameter, etc. Then one concrete split if there is an obvious one.

If nothing is over threshold, say so in one line. Do not pad the report.

## Notes

- Cyclomatic counts branches; cognitive punishes *nesting*. A function high in
  cognitive but low in cyclomatic is a nesting problem, not a branch-count problem.
- Non-Python repos get cyclomatic only — complexipy is Python-only.

## Drift check

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/complexity/drift.sh [base-ref]
```

Runs on the lines the branch **added**, never the whole file, so legacy code stays quiet.

- **Comment drift** — added-line comment ratio (`COMMENT_RATIO_MAX=25` %) and
  consecutive `#`/`//` blocks (`COMMENT_BLOCK_MAX=8`). Docstrings are not counted.
- **Slop patterns** — `uvx ruff` with: `ERA001` commented-out code, `F401`/`F841`
  unused import/variable, `ARG` unused argument, `RET504/RET505` pointless
  assign-before-return and `else` after `return`, `SIM` needless complexity,
  `PLR0913/PLR0911` too many args/returns, `PIE` dead code, `C4` needless
  comprehension calls. Python only. `ARG`, `PLR0913`, `ERA001` are off in test files.

Style rules (`UP`, line length, quotes) are deliberately excluded — they are the
project's business, not drift.

## Reporting drift

One line per hit, then the verdict. Do not auto-fix unless asked. A hit is a
question, not a defect: `ERA001` fires on type-shape notes, `PLR0913` on legitimate
DI constructors. Say which hits you think are real.

## CRAP check

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/complexity/crap.sh [base-ref] [coverage-file]
```

`CRAP = CCN^2 * (1 - coverage)^3 + CCN` per changed function. High = complex AND untested.
Complexity alone is not risk; complexity with no test is.

- Cyclomatic from `uvx lizard --csv`. Coverage from a report file you already produce:
  lcov (`lcov.info`), cobertura (`coverage.xml`), clover (`clover.xml`), Go (`coverage.out`).
  Auto-found in the usual paths, or pass the path / set `COV_FILE`.
- Threshold `CRAP_MAX=30` (the standard limit). Override via env.
- Reference points: CCN 4 fully untested = 20. CCN 6 untested = 42. CCN 10 at 50% cov = 135.
  Any function over 30 needs tests or a split — 30 is reachable at CCN 30 with full coverage,
  so a passing score means "tested, or simple enough not to need it".
- A file missing from the coverage report is counted as 0% and marked `*`. Check that the
  report is fresh and covers those files before trusting a `*` row.
- Self-check: `python3 ${CLAUDE_PLUGIN_ROOT}/skills/complexity/test_crap.py`

## Reporting CRAP

One line per function over threshold, exactly what the script printed. Then say the fix:
add tests (high CCN, low cov) or split the function (very high CCN). Do not report a function
just because it changed. No coverage report = say so and skip the section, do not estimate it.
