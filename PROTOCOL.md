# Reasoning battery — protocol

## Idea

The generator picks the answer first and builds the problem from it. Building is
cheap, solving is hard and checking is cheap. So a generator can make problems
harder than the model that wrote it can solve. Each run uses a fresh secret seed, so
no answer exists anywhere before the run.

The test has two stages:

1. **Calibrate.** Find the level at which the generating model solves 0–10% of the
   problems in each family. This is its frontier.
2. **Quiz.** Build a new set of problems at that frontier. The generating model runs it
   again blind, as a control. The candidate model runs the same quiz.

**Superiority = candidate success − generating-model success on the quiz, in
percentage points.** Example: the generating model scores 7% and the candidate scores
60%. The candidate is superior by 53 points.

## Provenance

| Item | Value |
|---|---|
| Generating model (baseline) | Claude Opus 5.5, model ID `claude-opus-5-5` |
| Environment | Claude Code desktop app |
| Date | 2026-11-18 |

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

### Stage 1 — Calibrate on the baseline

1. Generate the ladder with seed A:

   ```powershell
   ./ladder.ps1 -Mode Generate -Seed '<seed A>' -Dir ./ladder
   ```

2. Run the baseline on the ladder 3 times, into `./base1`, `./base2` and `./base3`.
   Copy `ladder/config.json` into each directory. Grade each one:

   ```powershell
   ./ladder.ps1 -Mode Verify -Seed '<seed A>' -Dir ./base1
   ```

3. Find the frontier: the lowest level where every baseline run solves at most 10%.

   ```powershell
   ./ladder.ps1 -Mode Calibrate -Dir ./cal -BaselineDir ./base1, ./base2, ./base3
   ```

   If a family warns "stays above 10%", raise `-MaxLevel`, then run stage 1 again for
   that family.

### Stage 2 — Blind quiz

1. **Commit.** Pick a new secret seed B. Publish its hash, which `Quiz` prints.

   ```powershell
   ./ladder.ps1 -Mode Quiz -Seed '<seed B>' -Dir ./quiz -Frontier ./cal/frontier.json
   ```

   The default is 15 problems per family (`-PerFamily`), so 105 prompts.

2. **Blind administration.** A neutral administrator, not the operator of either
   model, sends the prompts:
   - Tools, code execution, web and files off at the API level.
   - The same neutral system prompt, or none. The same output and reasoning budget.
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

   - A warning appears if the baseline scores above 10% on the quiz itself. The
     claim "the baseline solves 0–10%" then does not hold. Calibrate again.
   - A warning appears if the candidate is near 100% in a family. Its superiority is
     then only a lower bound. Build a second quiz at a higher level.

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
