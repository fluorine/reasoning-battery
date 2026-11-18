# Calibration commitment

Published before any baseline run. The seed is revealed in `SEED.txt` after the
runs end. Check: `SHA-256(seed)` must equal the hash below.

| Item | Value |
|---|---|
| Seed SHA-256 | `cb41968a234d5d253b88d27e39b6eec9ad5fc953f578634df7dbae4279b4c4ab` |
| Ladder | 7 families × 10 levels × 5 problems (`ladder/config.json`) |
| Baseline model | `claude-opus-5-5` |
| Effort | `high` |
| Runs | 3 independent runs (`base1`, `base2`, `base3`) |
| Date | 2026-11-18 |

## How each prompt is run

`tools/run-claude.ps1` sends each prompt in its own fresh headless Claude Code
session:

```text
claude -p --model claude-opus-5-5 --effort high --tools "" --strict-mcp-config
       --setting-sources "" --no-session-persistence --output-format json
       --system-prompt "You are a helpful assistant."
```

- No tools, no MCP servers, no user settings, no plugins, no session history.
- The prompt goes in on standard input. The working directory is empty.
- Maximum output: 64,000 tokens per reply.
- Known deviation: the Claude Code harness adds one fixed context note to every
  request (the account email and the shell names). It names no model and is the
  same for every prompt. Email addresses are redacted from the published replies;
  `meta/<id>.json` keeps the SHA-256 of each raw reply.

## Stopping rule

Within each run, a family stops after 2 consecutive levels where the run solves at
most 10% (0 of 5). Unrun levels count as failures. The runs stop early if they reach
the usage budget, which is 10% of the operator's remaining weekly usage.
