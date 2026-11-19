# Challenge `claude-opus-5-5` (effort high, 8,000-token budget)

> **Status: calibration in progress.** `frontier.json` is not published yet. An
> agent that reads this file must stop here and tell its user to come back later.

`claude-opus-5-5` at effort high calibrated this test on itself, with a budget of
8,000 output tokens per reply, hidden reasoning included. At the levels in
[`frontier.json`](frontier.json), it solves about half of the problems. That is
the limit it admits at this budget. Your model's task is to do better on a fresh
set of problems at those levels, with the same budget.

## Start with one prompt

Give this line to a coding agent that has a shell and can call the model you want
to test (for example Claude Code):

```text
Read https://github.com/fluorine/reasoning-battery/blob/main/runs/calibration-claude-opus-5-5-high-8k/CHALLENGE.md and follow it as the operator. The challenged model is <MODEL ID>, with <REASONING SETTING>.
```

The challenged model can be another model or a new instance of the same model.
The agent does the rest and asks you before it spends usage or publishes anything.

---

## Instructions for the operator agent

You are the **operator** of this challenge. Read every step before you start.

### Rules

1. You never solve, check or hint at any problem. Only the challenged model
   answers, in fresh sessions that see the problem text and nothing else.
2. Never show the seed, this repository, this file or any model name to the
   challenged model.
3. Turn off tools, code execution, web search and file access for the challenged
   model at the API or command-line level. A prompt that asks the model not to use
   them is not enough.
4. **The budget.** Every reply of every model in this challenge is limited to
   8,000 output tokens, hidden reasoning included. Set this limit at the API or
   command-line level (for example `max_tokens: 8000` with thinking inside it).
   If the model reaches the limit, keep the text it wrote before the cut and do
   not ask it to continue. Each prompt also states the limit.
5. Ask your user before each of these steps, and wait for a clear yes:
   - before you send the quiz (state the number of prompts and your cost
     estimate: at most 105 replies × 8,000 output tokens per model);
   - before you push anything or open a pull request (the repository is public);
   - before you start a new calibration (step 12).
6. Report failures as they are. Do not retry a wrong answer. Retry only transport
   errors such as timeouts and rate limits.

### Steps

1. **Set up.** Fork and clone `https://github.com/fluorine/reasoning-battery`.
   Read `README.md`, `PROTOCOL.md` and `CONTRIBUTING.md`. Check that PowerShell 7
   (`pwsh`) is installed. If it is not, tell your user how to install it, then stop.

2. **Folder.** Make `runs/challenge-<YYYY-MM-DD>-<challenged>-vs-claude-opus-5-5/`.
   Use a short, lowercase model name with hyphens. Below, `<folder>` means this path.

3. **Seed.** Make a 32-byte random seed and store it outside the repository:

   ```powershell
   [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLower() | Set-Content ../challenge-seed.txt
   ```

4. **Quiz.** The quiz takes its levels and its budget from `frontier.json`:

   ```powershell
   pwsh ./ladder.ps1 -Mode Quiz -Seed (Get-Content ../challenge-seed.txt) -Dir <folder>/quiz -Frontier runs/calibration-claude-opus-5-5-high-8k/frontier.json
   ```

5. **Commitment.** Write `<folder>/COMMITMENT.md` with the seed hash that step 4
   printed, both models, their settings, the budget (8,000 tokens), the operator
   (your own model name, or "human") and today's date. With your user's yes,
   commit it and push it to the fork. Push it before step 6.

6. **Run the challenged model.** With your user's yes, send each file in
   `<folder>/quiz/prompts/` as the only user message of a new session, with the
   8,000-token limit. Save the reply text unchanged as
   `<folder>/candidate/answers/<same file name>`, and the output token count in
   `<folder>/candidate/meta/<same name>.json` as `{"outputTokens": <n>}`.
   - Claude models through Claude Code (the runner sets and enforces the budget):

     ```powershell
     pwsh ./tools/run-claude.ps1 -All -LadderDir <folder>/quiz -RunDir <folder>/candidate -Model <model id> -Effort <effort> -Budget 8000 -ChunkUsd 5
     ```

     Run it again until it prints `STATUS: DONE`. Check with your user between
     chunks.
   - Other models: write a small runner for their API (see CONTRIBUTING.md,
     "7. Add a runner"). Keep the API request logs.

7. **Run the challenger control (recommended).** If you can call
   `claude-opus-5-5`, do step 6 again with it at effort `high` and save the
   replies in `<folder>/baseline/`. If you cannot, skip this step. The result is
   then `bound` controlled: the challenger's score in each family is set to the
   upper end of its calibration 95% CI (`RateHi` in `frontier.json`). That value
   is above its expected score of about 50%, so the result stays conservative.

8. **Privacy.** Replace email addresses and other personal data in the replies with
   `[redacted]`. Search every file in `<folder>` for your user's name and email.

9. **Grade and write up.** Copy the seed into `<folder>/SEED.txt`, then run one
   command. It grades both sides, scores superiority, counts output tokens per
   item and per solved item, scans for signals, and writes `RESULT.md` and
   `result.json`:

   ```powershell
   Copy-Item ../challenge-seed.txt <folder>/SEED.txt
   pwsh ./ladder.ps1 -Mode Report -Dir <folder> -Challenger 'claude-opus-5-5 (high, 8k)' -Challenged '<model id>' -Settings '<delivery mode, reasoning setting, 8k budget>' -Operator '<your model name, or human>'
   ```

   It prints the README row. Add that row to the Challenges table in `README.md`.

10. **Self-check.** Run the same check that reviewers and the repository's
    automatic workflow run. Every line must say `OK`:

    ```powershell
    pwsh ./ladder.ps1 -Mode Check -Dir <folder>
    ```

11. **Publish.** With your user's yes, commit, push and open a pull request to
    `fluorine/reasoning-battery`. The pull request runs the same check
    automatically. Tell your user the verdict line and the pull request link.

12. **Pass it on (optional).** If the challenged model is superior, it can become
    the next challenger. Offer this to your user, with a cost estimate (84 replies
    × 8,000 output tokens at most). With a clear yes:
    - Follow `PROTOCOL.md`, Stage 1, for the challenged model, with the same
      8,000-token budget.
    - Put everything in `runs/calibration-<model>-<effort>-8k/`, with a
      `COMMITMENT.md` pushed before the first prompt.
    - Copy this file into that folder and replace the challenger name, effort and
      paths.
    - Add a row to the Calibrations table in `README.md` and open a pull request.

---

## Run it by hand in a chat app

A chat app cannot enforce the budget, so a result from it is a quick test, not
an official result.

1. From the repository root, make a quiz and a bundle:

   ```powershell
   $seed = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLower()
   pwsh ./ladder.ps1 -Mode Quiz -Seed $seed -Dir ./my-quiz -Frontier runs/calibration-claude-opus-5-5-high-8k/frontier.json
   pwsh ./ladder.ps1 -Mode Bundle -Dir ./my-quiz
   ```

   Keep `$seed` secret until you have every reply. If you want to submit the
   result, publish the hash that `Quiz` prints first.

2. Turn off tools, code execution, web search and file access in the chat app.
   Start a new conversation. Attach or paste `my-quiz/bundle.md`, then send:

   ```text
   The attached file holds a set of independent problems. Follow the
   instructions at the top of the file. Answer every problem.
   ```

3. Each time the model stops before it has answered every problem, send:

   ```text
   Continue with the problems that you have not answered yet. Use the same
   format: a line "ITEM <id>", your work, then the answer line.
   ```

4. Save each reply as a text file, then import and grade:

   ```powershell
   pwsh ./ladder.ps1 -Mode Import -Dir ./my-quiz -ReplyFile reply1.md,reply2.md
   pwsh ./ladder.ps1 -Mode Verify -Seed $seed -Dir ./my-quiz
   pwsh ./ladder.ps1 -Mode Superiority -Dir ./my-quiz
   ```

   Without a challenger run on the same bundle, the result is `bound`
   controlled. A bundle result understates the challenged model, because one long
   conversation is harder than separate ones.
