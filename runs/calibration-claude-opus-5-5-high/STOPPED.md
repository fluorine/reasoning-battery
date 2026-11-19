# Stopped pilot

This calibration was stopped for cost on 2026-11-18. It has no frontier. Do not
challenge it. The budgeted staircase in
[`runs/calibration-claude-opus-5-5-high-8k/`](../calibration-claude-opus-5-5-high-8k/)
replaces it.

## What ran

| Item | Value |
|---|---|
| Plan | 3 runs × 7 families × 10 levels × 5 problems, no token budget (64,000-token cap per call) |
| Done | 51 replies in `pilot1/` (the run that was `base1`): `mult` levels 1–3, `sat` levels 1–8, `track` level 1 |
| Cost | 6.35 USD notional (sum of `costUsd` in `pilot1/meta/`) |
| Why it stopped | One run used about 9% of the operator's weekly usage, and hard problems used up to 49,579 output tokens each. The full plan was too expensive. |

`pilot1/results.csv` grades all 350 ladder items. An item with no reply counts as
wrong, so only the families and levels above have real data.

## Why the new design

- **A fixed token budget.** Every reply gets the same budget, and the prompt states
  it. The result then measures capacity per token, and the cost of a run has an
  upper limit.
- **A staircase.** Each family moves one level up after a correct answer and one
  level down after a wrong one. The trials then stay near the 50% point, where
  each trial tells the most.

## Check it

The seed is in `SEED.txt`. Its hash is in `COMMITMENT.md`, which was pushed before
the first reply.

```powershell
pwsh ./ladder.ps1 -Mode Check -Dir runs/calibration-claude-opus-5-5-high
```
