# Challenge `claude-opus-5-5` (effort high)

> **Status: calibration running.** `frontier.json` is not published yet. Do not
> start a challenge until this note is gone.

The challenger solves 0–10% of the problems at the levels in
[`frontier.json`](frontier.json). A challenged model that solves more is better at
this kind of reasoning, by the difference in points.

## Option 1 — Operator prompt for a coding agent

Paste this into a coding agent that has a shell and access to the challenged model
(for example Claude Code). Replace the two values in angle brackets. The agent
runs the whole challenge and prepares a pull request. It never answers the
problems itself.

```text
You are the operator of a reasoning-battery challenge. You never solve the
problems yourself, and you never show the seed, this repository or any model
name to the challenged model.

Challenged model: <MODEL ID AND HOW TO CALL IT>
Reasoning setting for the challenged model: <SETTING, FOR EXAMPLE effort high>
Challenger: claude-opus-5-5, effort high
Calibration: runs/calibration-claude-opus-5-5-high

1. Fork and clone https://github.com/fluorine/reasoning-battery. Read README.md,
   PROTOCOL.md and CONTRIBUTING.md. Check that PowerShell 7 is installed.
2. Make a folder runs/challenge-<today>-<challenged>-vs-claude-opus-5-5.
3. Make a 32-byte random seed. Store it outside the repository.
4. Run: pwsh ./ladder.ps1 -Mode Quiz -Seed <seed> -Dir <folder>/quiz
   -Frontier runs/calibration-claude-opus-5-5-high/frontier.json
5. Write <folder>/COMMITMENT.md with the seed hash that step 4 prints, the two
   models, their settings and the date. Commit it and push it to the fork
   before step 6.
6. For each file in <folder>/quiz/prompts, start a fresh conversation with the
   challenged model, with tools, code execution, web and files off at the API
   level. Send the file text as the only user message. Save the reply text
   unchanged as <folder>/candidate/answers/<same file name>. Retry only
   transport errors.
7. If you can call claude-opus-5-5, do step 6 again with it (effort high) and
   save the replies in <folder>/baseline/answers. If you cannot, skip this step.
8. Copy quiz/config.json into candidate/ (and baseline/). Then run:
   pwsh ./ladder.ps1 -Mode Verify -Seed <seed> -Dir <folder>/candidate
   pwsh ./ladder.ps1 -Mode Verify -Seed <seed> -Dir <folder>/baseline
   pwsh ./ladder.ps1 -Mode Superiority -Dir <folder>/candidate
     -BaselineDir <folder>/baseline    (leave out -BaselineDir if no step 7)
   pwsh ./ladder.ps1 -Mode Scan -Dir <folder>/candidate
9. Remove personal data such as email addresses from the replies.
10. Write <folder>/SEED.txt and <folder>/RESULT.md (the Superiority and Scan
    output, both models, all settings, dates). Add one row to the Challenges
    table in README.md as CONTRIBUTING.md shows.
11. Commit, push and open a pull request to fluorine/reasoning-battery.
    Report the verdict line to me.
```

## Option 2 — Run it by hand in a chat app

1. Make a quiz and a bundle (from the repository root):

   ```powershell
   $seed = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLower()
   pwsh ./ladder.ps1 -Mode Quiz -Seed $seed -Dir ./my-quiz -Frontier runs/calibration-claude-opus-5-5-high/frontier.json
   pwsh ./ladder.ps1 -Mode Bundle -Dir ./my-quiz
   ```

   Keep `$seed` secret until you have all the replies. Publish the hash that
   `Quiz` prints if you plan to submit the result.

2. Turn off tools, code execution, web search and file access in the chat app.
   Start a new conversation. Attach or paste `my-quiz/bundle.md` and send:

   ```text
   The attached file holds a set of independent problems. Follow the
   instructions at the top of the file. Answer every problem.
   ```

3. Each time the model stops before it has answered every problem, send:

   ```text
   Continue with the problems that you have not answered yet. Use the same
   format: a line "ITEM <id>", your work, then the answer line.
   ```

4. Save every reply as a text file, then import and grade them:

   ```powershell
   pwsh ./ladder.ps1 -Mode Import -Dir ./my-quiz -ReplyFile reply1.md,reply2.md
   pwsh ./ladder.ps1 -Mode Verify -Seed $seed -Dir ./my-quiz
   pwsh ./ladder.ps1 -Mode Superiority -Dir ./my-quiz
   ```

   Without a challenger run on the same bundle, the result is `ceiling`
   controlled. A bundle result understates the challenged model, because one long
   conversation is harder than separate ones.

## Option 3 — Manual steps

Follow [PROTOCOL.md](../../PROTOCOL.md), Stage 2, with
`-Frontier runs/calibration-claude-opus-5-5-high/frontier.json`.
