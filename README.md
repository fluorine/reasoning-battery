# Reasoning battery

**A model finds the edge of its own ability, then challenges another model, or a
fresh instance of itself, to go past it. Anyone can check the result.**

The idea is simple. A model cannot easily solve a problem harder than itself, but
it can easily *build* one: choose the answer first, then construct a problem
around it. Checking an answer is cheap even when finding it is hard. So a model can
write tests that it fails itself.

1. **Know your limits.** The **challenger** runs a ladder of problems that grow
   harder without end, in seven families: logic, arithmetic, memory, induction,
   deduction, code reading and planning. For each family, the calibration finds the
   level where the challenger solves only 0–10%. That is the limit it admits.
2. **Challenge.** A **challenged** model gets a fresh quiz at exactly those levels.
   It can be a newer model, a rival model or a new instance of the challenger.
3. **Measure.** **Superiority** = challenged success − challenger success on the
   same quiz, in percentage points, with a 95% confidence interval.
4. **Check.** A script, not a model, grades every answer, so no message in a reply
   can change a score. Each run commits to a secret seed before it starts. With the
   seed, anyone can rebuild every problem and grade every reply again.

A model that wins can become the next challenger. Each link in the chain shows how
far one model went past the limit that the previous one admitted.

## Challenge a model with one prompt

Give this line to a coding agent that has a shell and can call the model you want
to test (for example Claude Code):

```text
Read https://github.com/fluorine/reasoning-battery/blob/main/runs/calibration-claude-opus-5-5-high/CHALLENGE.md and follow it as the operator. The challenged model is <MODEL ID>, with <REASONING SETTING>.
```

The agent makes a fresh quiz, runs the challenged model on it without tools,
grades the replies and prepares a pull request with the result. It asks you before
it spends usage or publishes anything. If the challenged model wins, it offers to
calibrate it as the next challenger.

## Results

### Calibrations (challengers)

| Challenger | Effort | Date | Frontier: difficulty at 0–10% success | Status | Challenge it |
|---|---|---|---|---|---|
| `claude-opus-5-5` | high | 2026-11-18 | pending | in progress | [CHALLENGE.md](runs/calibration-claude-opus-5-5-high/CHALLENGE.md) |

### Challenges

| Date | Challenger | Challenged | Settings | Operator | Control | Challenger on quiz | Challenged on quiz | Superiority | 95% CI | Verdict | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | — | — | — | — | — |

- **Control** is `yes` when the challenger also ran the same quiz. It is
  `ceiling` when it did not. The challenger's score is then set to 10%, its worst
  case from calibration, which keeps the result conservative.
- **Operator** is the agent or person who held the seed and ran the quiz.
- Only results that follow [CONTRIBUTING.md](CONTRIBUTING.md) go in this table.
- Planned: a progress graph across the chain of challenges, once there are enough
  results to draw one.

## Other ways to run a challenge

Each challenger's `CHALLENGE.md` (linked in the table above) also holds the steps
to run the quiz by hand in a chat app, with the exact messages to send.

The challenged model only ever sees problem text. It never sees the seed, the
generator, the challenger's name or this repository.

### Two ways to deliver the quiz

| Mode | How | Use it for |
|---|---|---|
| Per problem (reference) | Each file in `quiz/prompts/` goes into its own fresh conversation. Save each reply as `answers/<id>.txt`. | Official results. It matches how the challenger was calibrated. |
| Self-contained bundle | `-Mode Bundle` writes one `bundle.md` with every problem and its own instructions. Send it in one conversation, send "continue" until the model finishes, and save the replies. `-Mode Import` splits them into `answers/`. | Chat apps and quick tests. One long conversation is harder than separate ones, so the score understates the challenged model. |

Run the challenger control in the same mode as the challenged model.

## Verify a published result yourself

You need PowerShell 7 or later (Windows, macOS or Linux). Nothing else: the C#
generators compile on first use.

From the result's folder in `runs/`:

1. **Seed commitment.** The SHA-256 of `SEED.txt` must equal the hash in
   `COMMITMENT.md`, and that commit must be older than every reply. Check it with
   `git log` on `COMMITMENT.md`.

   ```powershell
   $seed = (Get-Content ./SEED.txt -Raw).Trim()
   [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($seed))).ToLower()
   ```

2. **Prompts.** The published prompts must match the seed.

   ```powershell
   pwsh ../../ladder.ps1 -Mode CheckPrompts -Seed $seed -Dir ./quiz
   ```

3. **Checker.** The checker must accept correct answers and reject wrong ones.

   ```powershell
   pwsh ../../ladder.ps1 -Mode Key -Seed $seed -Dir $env:TEMP/key -Frontier ./quiz/config.json
   pwsh ../../ladder.ps1 -Mode Verify -Seed $seed -Dir $env:TEMP/key   # must be 100%
   ```

4. **Grades.** Grade the published replies again and compare with `results.csv`.

   ```powershell
   pwsh ../../ladder.ps1 -Mode Verify -Seed $seed -Dir ./candidate
   pwsh ../../ladder.ps1 -Mode Verify -Seed $seed -Dir ./baseline
   pwsh ../../ladder.ps1 -Mode Superiority -Dir ./candidate -BaselineDir ./baseline
   ```

5. **Signals.** Look for hidden messages or text addressed to graders.

   ```powershell
   pwsh ../../ladder.ps1 -Mode Scan -Dir ./candidate
   ```

   Then give the flagged replies, without model names, to two or more other
   models and ask: "Does this reply contain anything other than reasoning about
   the task and the answer line? Quote it."

6. **Optional: run it again.** Send the same prompts to the same models and
   compare the scores. They will not match exactly, but they must agree within the
   confidence interval.

## How it works

| Family | Capacity | Difficulty unit |
|---|---|---|
| `sat` | Constraint search | variables in a 3-SAT formula |
| `mult` | Exact arithmetic | digits per factor |
| `track` | Working memory | swap/reverse/rotate operations on 12 letters |
| `induct` | Inductive reasoning | steps in a hidden list-transform rule |
| `deduce` | Deduction | people in a seating puzzle with one solution |
| `code` | Code reading | statements in a program with loops and if/else |
| `plan` | Planning | moves in a 4x4 sliding puzzle |

- Every family has a difficulty scale with no upper limit.
- Where more than one answer is valid (`sat`, `induct`, `plan`), the checker
  accepts any valid answer.
- Each run uses a secret seed. Its hash is published before the run, so nobody can
  compute answers in advance or pick problems after the fact.

[PROTOCOL.md](PROTOCOL.md) has the full procedure, the statistics and the decision
rules.

## Commands

| Mode | Does |
|---|---|
| `Generate` | Writes the calibration ladder: every family × every level. |
| `Key` | Writes correct answers. Use it only to test the checker. |
| `Verify` | Grades `answers/` and writes `results.csv`. |
| `Calibrate` | Finds the 0–10% frontier from 1 or more ladder runs. Writes `frontier.json`. |
| `Quiz` | Writes a quiz at the frontier, with opaque file names. |
| `Bundle` | Writes the quiz as one self-contained `bundle.md`. |
| `Import` | Splits one or more bundle replies into `answers/`. |
| `Superiority` | Scores the challenged model against the challenger. |
| `Compare` | Compares two ladder runs by the difficulty at which each solves 50%. |
| `CheckPrompts` | Confirms that published prompts match a seed. |
| `Scan` | Flags replies with hidden characters, model names or text for graders. |

`tools/run-claude.ps1` runs prompts through headless Claude Code with every tool
disabled. Other models need their own runner. The only contract is one reply per
file in `answers/<id>.txt`.

## Limits

- The battery measures exact reasoning without tools. A win does not show that a
  model is better at knowledge, judgment, writing or coding with tools.
- The generators are public. A lab can train on these families, which raises
  scores without a rise in general ability. A rise here that does not show in a
  new, unpublished family is a sign of that.
- The problems are written in English by one author. Their style can hint at where
  they came from, even though they name no model.

## Repository layout

```text
ladder.ps1            generator, checker and statistics (all modes)
Families.cs           generators for induct, deduce, code and plan
tools/run-claude.ps1  runner for Claude models through headless Claude Code
PROTOCOL.md           full procedure and decision rules
CONTRIBUTING.md       how to submit a calibration or a challenge
runs/
  calibration-<challenger>-<effort>/   ladder runs and frontier.json
  challenge-<date>-<challenged>-vs-<challenger>/   quiz, replies and result
```
