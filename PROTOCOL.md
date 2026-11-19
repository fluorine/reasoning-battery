# Reasoning battery — protocol

## Idea

The generator picks the answer first and builds the problem from it. Building is
cheap, solving is hard and checking is cheap. So a generator can make problems
harder than the model that wrote it can solve. Each run uses a fresh secret seed, so
no answer exists anywhere before the run.

Every reply has the same fixed **token budget**: 8,000 output tokens, hidden
reasoning included. The prompt states it, and the runner enforces it. So the test
measures reasoning capacity at a fixed budget ("intelligence per token"), and the
cost of a run has an upper limit.

**The test is blind.** The model under test sees only the problem: the rules (no
tools, the token budget) and the answer format. No prompt names a model, a
challenger, a comparison or this repository. `Generate`, `Staircase`, `Quiz` and
`Bundle` stop with an error if a prompt does, and `CheckPrompts` (so `Check` and
the GitHub workflow) fails on a published prompt that does. The system prompt is
neutral ("You are a helpful assistant.") and the same for every model.

The battery has two uses. As a **benchmark**, a calibration gives a model an
absolute score per family: `d50`, the difficulty at which it solves 50% within the
budget, and its output tokens per solved problem. As a **challenge**, a quiz at one
model's frontier shows whether another model goes past it. One calibration serves
both. It works as a benchmark because a script grades every reply (no LLM judge),
a fresh secret seed per run stops contamination, difficulty has no ceiling, and
the fixed budget builds efficiency into the score. Its limits: it measures only
exact reasoning without tools, its public generators can be trained on (the
defence is private and rotated families), and `d50` values are comparable only at
the same budget and delivery mode.

The test has two stages:

1. **Calibrate.** A staircase finds the level at which the generating model solves
   about 50% of the problems in each family, at the budget. This is its frontier.
2. **Quiz.** Build a new set of problems at that frontier. The generating model runs it
   again blind, as a control. The candidate model runs the same quiz, with the same
   budget.

**Superiority = candidate success − generating-model success on the quiz, in
percentage points.** Example: the generating model scores 48% and the candidate scores
80%. The candidate is superior by 32 points.

The frontier is at 50%, not near 0%, because a trial near 50% tells the most about
where the limit is, and because a quiz at 50% can show a gain and also a loss.

## Provenance

| Item | Value |
|---|---|
| Generating model (baseline) | Claude Opus 5.5, model ID `claude-opus-5-5` |
| Environment | Claude Code desktop app |
| Date | 2026-11-18 (design), 2026-11-19 (budgeted staircase) |

Terms used in this document:

- **Baseline:** the generating model above. You may also call it the challenger.
- **Candidate:** the model under test, also called the challenged model.

This provenance stays in this document only. The quiz does not show it:

- The prompts contain no model, vendor or author name. `Generate` and `Quiz` stop
  with an error if any prompt names a known model or vendor.
- Quiz files have opaque names (`04749ab5d49d.txt`). The names do not show the family,
  the level or the order of generation.
- Never give `config.json`, `frontier.json` or this document to a model under test.

## Families

| Family | Capacity | Difficulty unit | Check |
|---|---|---|---|
| `sat` | Constraint search | variables (4.2 clauses each) | Any assignment that satisfies all clauses |
| `mult` | Exact arithmetic | digits per factor | Big-integer product |
| `track` | Working memory | swap/reverse/rotate operations | Replay |
| `induct` | Inductive reasoning | steps in a hidden list-transform rule | Any rule within the step limit that reproduces all examples |
| `deduce` | Deduction | people in a seating puzzle with exactly one solution | Exact seating |
| `code` | Code reading | statements (with loops and if/else) | Final variable values |
| `plan` | Planning | moves in a 4x4 sliding puzzle | Replay. Must reach the goal within the move limit |

Level L has difficulty `round(Base × Growth^(L-1))`, and each level is at least 1 above
the level before it. There is no upper limit.

## Procedure

### The token budget

- Every prompt states the budget in its rules: "Your whole reply, including any
  hidden reasoning, is limited to 8,000 tokens." `-Budget` sets it (default 8,000;
  0 states no limit). `config.json` and `frontier.json` record it, and a quiz takes
  the budget of its frontier.
- The runner enforces the budget at the API or command-line level. A reply that
  reaches it is cut there. The text before the cut is graded as it is, and the
  runner does not ask the model to continue.
- `tools/run-claude.ps1` sets `CLAUDE_CODE_MAX_OUTPUT_TOKENS`. That cap applies to
  one API call, hidden reasoning included. When a call reaches it, Claude Code asks
  the model to continue in a new call, so the runner stops the process at that
  point. `meta/<id>.json` marks a cut reply with `cutAtBudget: true`.

### Stage 1 — Calibrate on the baseline (staircase)

1. Commit to a secret seed A: push its hash in `COMMITMENT.md`. Then start the
   staircase. It writes `config.json` and the first prompt of each family:

   ```powershell
   ./ladder.ps1 -Mode Staircase -Seed '<seed A>' -Dir ./stair1 -Budget 8000 -Trials 12 -Start 3
   ```

2. Run the baseline. The runner sends each pending prompt, saves the reply, then
   runs `-Mode Staircase` again, which grades the reply and writes the next prompt
   of that family:

   ```powershell
   ./tools/run-claude.ps1 -Staircase -RunDir ./stair1 -SeedFile <file with seed A> -Effort high -Budget 8000
   ```

   The rules:
   - Each family starts at level 3 (`-Start`).
   - After a correct answer, the next trial is one level higher. After a wrong
     answer, it is one level lower. The lowest level is 1. There is no highest
     level.
   - Each trial is a new problem. Its id names the family, the level and the trial,
     for example `sat-L05-t07`.
   - A family stops after 12 trials (`-Trials`).

3. Find the frontier:

   ```powershell
   ./ladder.ps1 -Mode Calibrate -Dir ./cal -BaselineDir ./stair1
   ```

   For each family, it pools the trials per level, fits a monotone (isotonic)
   success curve, and finds the difficulty where the curve crosses 50% (`d50`),
   interpolated on a log scale. The frontier is the level whose difficulty is
   nearest to `d50`. `frontier.json` also holds:
   - `Rate`: the fitted success rate at that level;
   - `RateHi`: the upper end of its 95% Wilson interval, over the trials that the
     fit pools with that level;
   - `TokensPerItem` and `TokensPerSolved`: output tokens per trial and per correct
     trial.

   More runs (`stair2`, `stair3`, each with its own `Run` name and so its own
   problems) make the frontier more precise. `Calibrate` pools them.

The earlier design ran a fixed ladder (every family × 10 levels × 5 problems, 3
runs) and put the frontier at 0–10%. `-Mode Generate` and `-Mode Calibrate` on
ladder runs still work. That design cost too much: see
`runs/calibration-claude-opus-5-5-high/STOPPED.md`.

### Stage 2 — Blind quiz

1. **Commit.** Pick a new secret seed B. Publish its hash, which `Quiz` prints.

   ```powershell
   ./ladder.ps1 -Mode Quiz -Seed '<seed B>' -Dir ./quiz -Frontier ./cal/frontier.json
   ```

   The default is 15 problems per family (`-PerFamily`), so 105 prompts.

2. **Blind administration.** A neutral administrator, not the operator of either
   model, sends the prompts:
   - Tools, code execution, web and files off at the API level.
   - The same neutral system prompt, or none. The same token budget, set at the API level.
   - One fresh conversation per prompt, in random order. No retries.
   - The administrator stores each model's replies under a random label (for example
     `set-k7q2`), not under the model name. It publishes the SHA-256 of the
     label-to-model mapping and reveals the mapping only after the audit.
   - The baseline control run uses fresh baseline instances. Nothing in their prompts
     tells them that they generated the test.

3. **Grade each set.** Copy `quiz/config.json` into each set directory, then:

   ```powershell
   ./ladder.ps1 -Mode Verify -Seed '<seed B>' -Dir ./set-k7q2
   ```

4. **Score.**

   ```powershell
   ./ladder.ps1 -Mode Superiority -Dir ./candidate-set -BaselineDir ./baseline-set
   ```

   Output for each family and overall: baseline success, candidate success,
   superiority in points with a paired-bootstrap 95% CI, and the share of the
   baseline's failures that the candidate solved.

   - A warning appears if the baseline scores above `RateHi` in a family. The
     frontier is then easier for it than the calibration says. Sharpen the
     calibration with more trials.
   - A warning appears if the candidate is near 100% in a family. Its superiority is
     then only a lower bound. Build a second quiz at a higher level.
   - Without a baseline control run, the baseline's score in each family is set to
     `RateHi`, the upper end of its calibration CI. Its expected score is about
     50%, so this choice makes an uncontrolled result conservative. The output says
     `UNCONTROLLED`, and the README row says `bound`. (A quiz from an old 0–10%
     ladder frontier uses its 10% ceiling instead, and says `ceiling`.)
   - `-Mode Report` also gives the output tokens per item and per solved item for
     each side, from `meta/<id>.json`.

### Results presented by the candidate's side

The candidate's operator can run the quiz, but a self-reported score is never accepted.
Only the raw replies plus the API logs count. The script grades them again from the
revealed seed.

## Decision rule (fix it before any run)

`VERDICT: candidate superior by X points` only if the lower bound of the overall 95%
CI is above 0. Report X with its CI, and the per-family table. Do not report one
number without the table.

## Blind audit for signals and cheating

Grading is a deterministic script, so no message in a reply can change a score. The
audit looks for attempts to signal or to cheat, which disqualify a set.

1. **Automatic pre-scan** of each anonymized set:

   ```powershell
   ./ladder.ps1 -Mode Scan -Dir ./set-k7q2
   ```

   It flags invisible or bidirectional Unicode, Unicode tag characters, model or
   vendor names, words that address the test or its graders, long encoded-looking
   tokens, and text after the final answer line.

2. **Blind auditors.** Give each anonymized set and its scan report to at least 2 third-party
   models and to fresh instances of both the baseline and the candidate. No auditor
   knows which set belongs to which model. Each auditor answers, per flagged reply and
   for a random sample of the others: "Does this reply contain anything other than
   reasoning about the task and the answer line? Quote it."

3. **Integrity checks:**
   - [ ] `SHA-256(seed)` equals the hash published before the runs.
   - [ ] Prompts regenerated from the seed are byte-identical to the prompts sent.
   - [ ] API logs show tools disabled and zero tool calls.
   - [ ] Each reply file equals the raw API output.
   - [ ] `-Mode Key` (with `-Frontier` for a quiz) into an empty directory, then
         `-Mode Verify`, scores 100%.
   - [ ] A one-character change to a key answer makes that item fail.
   - [ ] The label-to-model mapping matches its published hash.

## Does a new seed stop adaptation?

Partly.

- **It stops memorized answers.** No problem or answer exists before the run, so
  benchmark contamination is impossible.
- **It does not stop training on the families.** The generator code shows the
  distribution. A lab can generate millions of problems and train on them.

Countermeasures, strongest first:

1. **Keep some families private.** Release a private family only after it has been
   used.
2. **Rotate families.** If scores rise on the published families but not on a new
   one, someone trained on the test.
3. **Vary the surface on every run.** The generators already shuffle names, variable
   names and the order of the operation list.
4. **Check that it measures what you want.** Run the battery on model pairs whose
   order you already know.

## Other modes

`Compare` reports the ratio of the difficulty at which each model solves 50%
(`d50_candidate / d50_best_baseline`) from two ladder runs. Use it when the candidate
saturates the quiz.
