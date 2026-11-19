# Calibration commitment

Published before the first prompt. The seed is revealed in `SEED.txt` after the
run ends. Check: `SHA-256(seed)` must equal the hash below.

| Item | Value |
|---|---|
| Seed SHA-256 | `71076fad146f46bcc9b93e9ddbc2352b89847897069058d30af743c7c0936582` |
| Challenger | `claude-opus-5-5` |
| Effort | `high` |
| Budget | 8,000 output tokens per reply, hidden reasoning included |
| Design | Staircase, 1 run (`stair1/`), 7 families × 12 trials (`stair1/config.json`) |
| Date | 2026-11-19 |

## Staircase rules

1. Each family starts at level 3.
2. After a correct answer, the next trial is one level higher. After a wrong
   answer, it is one level lower. The lowest level is 1. There is no highest level.
3. Each trial is a new problem from the seed. Its id names the family, the level
   and the trial number, for example `sat-L05-t07`. No problem repeats.
4. A family stops after 12 trials.
5. `-Mode Calibrate` fits a monotone success curve per family over all trials,
   finds the difficulty where it crosses 50% (`d50`), and picks the level nearest
   to `d50`. That level goes in `frontier.json`, with the fitted success rate and
   the upper end of its 95% CI.

`-Mode Check` replays the rules from the seed and the replies. A reply that is not
on the path that the rules give fails the check.

## How each prompt is run

`tools/run-claude.ps1 -Staircase` sends each prompt in its own fresh headless
Claude Code session:

```text
CLAUDE_CODE_MAX_OUTPUT_TOKENS=8000
claude -p --model claude-opus-5-5 --effort high --tools "" --strict-mcp-config
       --setting-sources "" --no-session-persistence --output-format stream-json
       --verbose --system-prompt "You are a helpful assistant."
```

- No tools, no MCP servers, no user settings, no plugins, no session history.
- The prompt goes in on standard input. The working directory is empty.
- Every prompt states the budget in its rules: "Your whole reply, including any
  hidden reasoning, is limited to 8,000 tokens."
- The cap applies to one API call, hidden reasoning included. When a call reaches
  the cap, Claude Code asks the model to continue in a new call. The runner stops
  the process at that point. The reply is then the text written before the cap,
  often none, and it is graded as it is. `meta/<id>.json` marks it with
  `cutAtBudget: true`.
- Known deviation: the Claude Code harness adds one fixed context note to every
  request (the account email and the shell names). It names no model and is the
  same for every prompt. Email addresses are redacted from the published replies.
  `meta/<id>.json` keeps the SHA-256 of each raw reply.
- Transport errors are retried. Wrong answers are not.

## Usage limit

The run stops before the operator's weekly usage passes 60%, and pauses when the
5-hour window passes 90%. If it stops early, the trials done so far are published
and the shortfall is stated.
