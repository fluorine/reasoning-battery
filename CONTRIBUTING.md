# Submitting a result

Results enter the README tables through pull requests. A result counts only when
anyone can check it again from the files in its folder.

## Rules

1. **Commit before you run.** Push `COMMITMENT.md` with the seed hash to your fork
   before you send the first prompt. Reviewers compare that commit time with the
   reply times.
2. **No tools.** Turn off tools, code execution, web search and file access at the
   API or app level for every model in the run. Do not rely on a prompt that asks
   the model not to use them.
3. **Same conditions.** The challenger control and the challenged model get the
   same delivery mode, the same system prompt (or none) and comparable reasoning
   settings. Record the settings in `RESULT.md`.
4. **No retries, no selection.** Each problem gets one attempt. A transport error
   (timeout, rate limit, server error) may be retried. A wrong answer may not.
5. **Raw replies.** Commit each reply as the model returned it. The only allowed
   change is the redaction of personal data such as email addresses. If you redact,
   keep the SHA-256 of the raw reply.
6. **No self-reported scores.** Reviewers grade the replies again from the seed.
   A score in `RESULT.md` that the script does not reproduce is rejected.
7. **The operator is not the challenged model.** The agent or person who holds the
   seed must not answer problems. The challenged model only ever sees problem text.

## A challenge folder

Name it `runs/challenge-<YYYY-MM-DD>-<challenged>-vs-<challenger>/`.

```text
COMMITMENT.md     seed hash, models, settings, date (pushed before the run)
SEED.txt          the seed (added after the run)
quiz/             config.json and prompts/ from -Mode Quiz
candidate/        answers/, meta/ (optional), results.csv
baseline/         the challenger control: answers/, results.csv (omit if none)
RESULT.md         output of -Mode Superiority and -Mode Scan, plus settings
```

## A calibration folder

Name it `runs/calibration-<challenger>-<effort>/`. Use 3 ladder runs
(`base1`, `base2`, `base3`) and the stopping rule in `PROTOCOL.md`. Add
`frontier.json` from `-Mode Calibrate` and a `CHALLENGE.md` made from the one in
`runs/calibration-claude-opus-5-5-high/`.

## The table row

Add one row to the right table in `README.md`. For a challenge:

```markdown
| 2026-12-01 | `claude-opus-5-5` (high) | `<challenged-model-id>` | per problem, <reasoning setting> | yes | 6% | 58% | +52 | +43 to +61 | superior | [folder](runs/challenge-2026-12-01-<challenged>-vs-claude-opus-5-5/) |
```

- **Control:** `yes` with a challenger control run, `ceiling` without one.
- **Verdict:** `superior` only when the lower CI bound is above 0. Otherwise
  `not shown`.

## Pull request checklist

- [ ] `COMMITMENT.md` was pushed before the first prompt was sent.
- [ ] `CheckPrompts` reports 0 mismatches.
- [ ] `Verify` reproduces every `results.csv`.
- [ ] `Superiority` reproduces the numbers in `RESULT.md` and in the table row.
- [ ] `Scan` output is in `RESULT.md`. Each flagged reply is explained.
- [ ] No personal data in any file.
