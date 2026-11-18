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

| Date | Challenger | Challenged | Settings | Operator | Control | Challenger on quiz | Challenged on quiz | Superiority | 95% CI | Verdict | Checks | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | — | — | — | — | — | — |

- **Control** is `yes` when the challenger also ran the same quiz. It is
  `ceiling` when it did not. The challenger's score is then set to 10%, its worst
  case from calibration, which keeps the result conservative.
- **Operator** is the agent or person who held the seed and ran the quiz.
- **Checks** is the number of independent people who reproduced or replicated the
  result. See `VERIFICATIONS.md` in its folder.
- Only results that follow [CONTRIBUTING.md](CONTRIBUTING.md) go in this table.
- Planned: a progress graph across the chain of challenges, once there are enough
  results to draw one.

## Contribute

You do not need model access to help. Each entry in [PROMPTS.md](PROMPTS.md) is
one line to give a coding agent:

| Prompt this to… | What happens |
|---|---|
| challenge a model | A fresh quiz runs against a published challenger. |
| write a challenge for another model | Your model finds its own limit, then challenges another model to go past it. |
| repeat a test | The same quiz runs again on the same models, to test whether a result was luck. |
| check a published result | The problems are rebuilt from the seed and the replies are graded again. No model access needed. |
| audit replies for hidden signals | The replies are searched for hidden characters, encoded text or messages to graders. |
| make a new challenger only | A model, often the last winner, is calibrated so that others can challenge it. |
| sharpen a calibration | More runs make a frontier more precise. |
| add a runner for another provider | The battery gets support for another model provider. |
| propose a new task family | A family that no model has trained on is added. |
| report a problem | An issue is drafted for a checker or prompt problem. |

[CONTRIBUTING.md](CONTRIBUTING.md) has the steps, the rules and the folder layouts.

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
generators compile on first use. From the repository root:

```powershell
pwsh ./ladder.ps1 -Mode Check -Dir runs/<folder>
```

One command checks a challenge folder or a calibration folder:

| Line | What it proves |
|---|---|
| Seed matches commitment | The seed was fixed before the run. Also check with `git log` that `COMMITMENT.md` is older than every reply. |
| Prompts match seed | Nobody picked or edited problems after the fact. |
| Grades reproduce | Every published grade is what the checker gives. |
| Superiority reproduces / Frontier reproduces | The headline numbers follow from the graded replies. |
| Scan flagged N replies | Replies with hidden characters, model names or text for graders, for a human or other models to read. |

Every pull request that changes `runs/` runs the same check automatically, with the
checker from the base branch. Try it first on the worked example in
`examples/challenge-2026-11-18-synthetic-vs-synthetic`.

To test whether a result was luck, repeat it: send the same prompts to the same
models and compare. See "Prompt this to repeat a test" in [PROMPTS.md](PROMPTS.md).

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
| `Report` | Grades a challenge folder and writes `RESULT.md`, `result.json` and the README row. |
| `Check` | Checks a published challenge or calibration folder end to end. Exit code 1 on any failure. |

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
.github/workflows/    automatic check of every result in a pull request
examples/             a worked example with a public seed (not a real result)
PROTOCOL.md           full procedure and decision rules
CONTRIBUTING.md       how to submit a calibration or a challenge
runs/
  calibration-<challenger>-<effort>/   ladder runs and frontier.json
  challenge-<date>-<challenged>-vs-<challenger>/   quiz, replies and result
```
