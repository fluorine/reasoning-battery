# Contributing

Every contribution arrives as a pull request or an issue. A result counts only when
anyone can check it again from the files in its folder.

[PROMPTS.md](PROMPTS.md) has a one-line prompt for each kind of contribution. Give
it to a coding agent, and the agent follows this file.

## Rules for agents

If you are an agent that works on this repository for a user, these rules apply to
every task here.

1. Ask your user, and wait for a clear yes, before you:
   - send any prompt to a model (state the number of prompts and your cost
     estimate);
   - push anything, open a pull request or open an issue (the repository is
     public);
   - start a calibration or a replication.
2. Never solve, check or hint at a problem that a model under test will answer.
   Models under test answer in fresh sessions that see only the problem text.
3. Never show a secret seed, this repository or a challenger's name to a model
   under test.
4. Keep the test blind. Never tell a model under test what the test is, who set
   it, that it is a challenge or a benchmark, or that another model takes it. It
   gets only the problem text, with a neutral system prompt ("You are a helpful
   assistant.") or none. The challenger control and the challenged model get the
   same prompts and the same system prompt.
5. Before you publish, search every new file for personal data, such as your
   user's name and email address, and replace it with `[redacted]`.
6. Report outcomes as they are, including failures and numbers that do not
   reproduce.

## Ways to contribute

| Contribution | Effort | Needs model access | Where it goes |
|---|---|---|---|
| [Check a published result](#1-check-a-published-result) | 10 minutes | No | `VERIFICATIONS.md` in the result's folder |
| [Replicate a result](#2-replicate-a-result) | Hours | Yes | `VERIFICATIONS.md` in the result's folder |
| [Audit replies for signals](#3-audit-replies-for-signals) | 1 hour | Optional | `VERIFICATIONS.md`, or an issue |
| [Challenge a model](#4-challenge-a-model) | Hours | Yes | A new `runs/challenge-…/` folder and a table row |
| [Benchmark a model or calibrate a new challenger](#5-benchmark-a-model-or-calibrate-a-new-challenger) | Hours | Yes | A new `runs/calibration-…/` folder, a leaderboard row and a calibrations row |
| [Sharpen a calibration](#6-sharpen-a-calibration) | Hours | Yes | More runs in an existing calibration folder |
| [Add a runner for another provider](#7-add-a-runner) | Hours | Yes | `tools/run-<provider>.ps1` |
| [Propose a new task family](#8-propose-a-new-task-family) | Days | No | `Families.cs`, `ladder.ps1`, `PROTOCOL.md` |
| [Report a checker or prompt problem](#9-report-a-problem) | Minutes | No | An issue |

### 1. Check a published result

You need only PowerShell 7. One command checks a challenge folder or a calibration
folder: the seed against its commitment, the prompts against the seed, every grade,
the superiority numbers or the frontier, and the signal scan.

```powershell
pwsh ./ladder.ps1 -Mode Check -Dir runs/<folder> -Who '@your-handle'
```

It prints the row to add to `VERIFICATIONS.md` in that folder (make the file if it
does not exist, with this header):

```markdown
| Date | Who | Kind | Steps done | Outcome | Notes |
|---|---|---|---|---|---|
```

- **Outcome:** `reproduced` when every line says `OK`, `differs` when one says
  `FAIL`. For `differs`, also open an issue that quotes the output.
- Increase the **Checks** count of that row in the README table by one.
- Try it first on `examples/challenge-2026-11-18-synthetic-vs-synthetic`, a worked
  example with a public seed.

### 2. Replicate a result

A replication sends the published quiz prompts to the same models again, in fresh
sessions, with the same settings. It tests whether the result was luck.

1. Use the published `quiz/prompts/` unchanged. Do not make a new quiz.
2. Follow the run rules below (tools off, one attempt, raw replies).
3. Put the replies in `<result folder>/replications/<your-handle>-<date>/`
   (`candidate/`, and `baseline/` if you ran the control).
4. Grade them with the published seed and run `Superiority`.
5. Add a row with Kind `replication` to `VERIFICATIONS.md`. The outcome is
   `consistent` when your superiority falls inside the published 95% CI, and
   `inconsistent` when it does not.

The seed is public at this point, so anyone can compute the answers. That does not
matter for the model, which sees only the problem text with its tools off, but
reviewers then rely on your API logs. Keep them.

### 3. Audit replies for signals

Look for anything in a reply other than reasoning about the task and the answer
line: hidden characters, encoded text, text addressed to graders, claims about the
model's identity.

1. Run `pwsh ./ladder.ps1 -Mode Scan -Dir <folder>/candidate` (and `baseline`).
2. Read every flagged reply and a random sample of 10 others. Better still, give
   them without model names to two or more other models and ask: "Does this reply
   contain anything other than reasoning about the task and the answer line? Quote
   it."
3. Add a row with Kind `audit` to `VERIFICATIONS.md`, or open an issue that quotes
   what you found.

### 4. Challenge a model

Give one line to a coding agent, as the [README](README.md) shows, or follow the
challenger's `CHALLENGE.md` by hand. Then follow the run rules, the folder layout
and the pull request checklist below.

### 5. Benchmark a model or calibrate a new challenger

One staircase calibration does both. It gives the model a row in the benchmark
leaderboard (its `d50` and tokens per solved problem in each family), and it
makes the model a challenger that others can try to go past. Any model can take
it, and a model that wins a challenge is the natural next challenger. This is how
the chain grows.

1. Follow `PROTOCOL.md`, Stage 1: make a new secret seed, push `COMMITMENT.md`,
   start the staircase with `-Mode Staircase`, run it with the runner, then run
   `-Mode Calibrate`. Use the 8,000-token budget, so that the new challenger is
   comparable with the others.
2. Cost: at most 7 families × 12 trials × 8,000 output tokens. Easy trials use
   much less.
3. Use the folder layout for a calibration below.
4. Copy `runs/calibration-claude-opus-5-5-high-8k/CHALLENGE.md` into the new
   folder. Replace the challenger name, effort and paths. Remove the status note
   when `frontier.json` is in place.
5. Add a row to the Benchmark leaderboard in the README: the `D50` and `Unit` of
   each family from `frontier.json` (for example "sat 37 variables"), and the
   tokens per solved problem.
6. Add a row to the Calibrations table in the README, with the frontier level and
   tokens per solved problem of each family.

If `Calibrate` warns that the 50% point is outside the visited levels, the
staircase did not reach the model's limit in that family. The family stays out of
`frontier.json` (it is listed under `Uncalibrated`). To add it, run more trials,
for example a second run with a higher `-Start`.

### 6. Sharpen a calibration

A frontier from one staircase of 12 trials per family is coarse. More runs make it
more precise. Add `stair2`, `stair3` and so on to an existing calibration folder,
with the same seed, budget and settings (each run's name changes its problems),
then run `-Mode Calibrate` over all the runs. If the
frontier changes, say so in the pull request: challenges made with the old frontier
stay valid, but new ones use the new file.

### 7. Add a runner

`tools/run-claude.ps1` covers Claude models through Claude Code. Other providers
need their own runner. The contract:

- One fresh session per prompt. The prompt file is the only user message.
- Tools, code execution, web and file access off at the API level.
- The token budget set at the API level, hidden reasoning included. A reply that
  reaches it is cut there and graded as it is. Never ask the model to continue.
- The reply text goes unchanged into `answers/<id>.txt`. Metadata (model, settings,
  tokens, cost, the SHA-256 of the raw reply) goes into `meta/<id>.json`.
- Transport errors may be retried. Wrong answers may not.
- `-All` runs a whole quiz. `-Staircase` grades each reply with
  `ladder.ps1 -Mode Staircase` and sends the next trial that it writes.

Name it `tools/run-<provider>.ps1`, and document its settings at the top.

### 8. Propose a new task family

New families keep the battery ahead of training: a family that nobody has trained
on shows whether a gain is general. A family must:

1. Build each problem from an answer it holds, from a seeded `System.Random`.
2. Have one difficulty number per level that can grow without limit.
3. Check an answer cheaply, and accept every valid answer, not only the planted
   one.
4. Pass `-Mode Key` followed by `-Mode Verify` at 100%, and reject wrong answers.
5. Name no model, vendor or author in its prompt text.

Open an issue first to discuss the idea. A family that you keep private until it
has been used once is worth more than a published one. Say so in the issue, and
the maintainers will agree on how to release it.

### 9. Report a problem

Open an issue when the checker rejects a valid answer, accepts a wrong one, or a
prompt is ambiguous. Quote the item id, the seed (if public), the reply, and the
command that you ran.

## Run rules

These apply to every run: challenges, calibrations and replications.

1. **Commit before you run.** Push `COMMITMENT.md` with the seed hash to your fork
   before you send the first prompt. Reviewers compare that commit time with the
   reply times.
2. **No tools.** Turn off tools, code execution, web search and file access at the
   API or app level for every model in the run. Do not rely on a prompt that asks
   the model not to use them.
3. **Same conditions.** The challenger control and the challenged model get the
   same delivery mode, the same system prompt (or none), the same token budget and
   comparable reasoning settings. Record the settings in `RESULT.md`.
4. **No retries, no selection.** Each problem gets one attempt. A transport error
   (timeout, rate limit, server error) may be retried. A wrong answer may not.
5. **Raw replies.** Commit each reply as the model returned it. The only allowed
   change is the redaction of personal data such as email addresses. If you redact,
   keep the SHA-256 of the raw reply.
6. **No self-reported scores.** Reviewers grade the replies again from the seed.
   A score in `RESULT.md` that the script does not reproduce is rejected.
7. **The operator never answers.** The agent or person who holds the seed must not
   solve, check or hint at any problem. The challenged model answers in separate,
   fresh sessions that see only problem text. The operator can be the same model
   as the challenged one, but it must be named in `RESULT.md` and in the table.

## Folder layouts

### A challenge folder

Name it `runs/challenge-<YYYY-MM-DD>-<challenged>-vs-<challenger>/`.

```text
COMMITMENT.md      seed hash, models, settings, operator, date (pushed before the run)
SEED.txt           the seed (added after the run)
quiz/              config.json and prompts/ from -Mode Quiz
candidate/         answers/, meta/ (optional), results.csv
baseline/          the challenger control: answers/, results.csv (omit if none)
RESULT.md          output of -Mode Superiority and -Mode Scan, plus settings
VERIFICATIONS.md   checks, replications and audits by other people
replications/      replies from replications
```

### A calibration folder

Name it `runs/calibration-<challenger>-<effort>-<budget>/`, for example
`calibration-claude-opus-5-5-high-8k`.

```text
COMMITMENT.md      seed hash, model, settings, budget, date (pushed before the run)
SEED.txt           the seed (added after the runs)
stair1/ stair2/ …  config.json, prompts/, answers/, meta/, results.csv per run
frontier.json      output of -Mode Calibrate
CHALLENGE.md       instructions for challengers
VERIFICATIONS.md   checks by other people
```

## The table rows

Add one row to the right table in `README.md`. For a challenge:

```markdown
| 2026-12-01 | `claude-opus-5-5 (high, 8k)` | `<challenged-model-id>` | per problem, <reasoning setting>, 8k budget | <operator> | yes | 48% | 81% | +33 | +22 to +44 | 5,120 / 3,870 | superior | 0 | [folder](runs/challenge-2026-12-01-<challenged>-vs-claude-opus-5-5/) |
```

- **Control:** `yes` with a challenger control run, `bound` without one.
- **Tokens per solved:** from `-Mode Report`. `n/a` when a side has no
  `meta/` files.
- **Verdict:** `superior` only when the lower CI bound is above 0. Otherwise
  `not shown`.
- **Checks:** the number of rows in `VERIFICATIONS.md` with outcome
  `reproduced` or `consistent`. A new result starts at 0.

## Pull request checklist

- [ ] `COMMITMENT.md` was pushed before the first prompt was sent.
- [ ] `RESULT.md`, `result.json` and the table row come from `-Mode Report`.
- [ ] `-Mode Check` says `OK` on every line. Each flagged reply is explained.
- [ ] No personal data in any file.

Every pull request that changes `runs/` or `examples/` runs `-Mode Check`
automatically, with the checker from the base branch. The report is in the
pull request's Checks tab, under the job summary.
