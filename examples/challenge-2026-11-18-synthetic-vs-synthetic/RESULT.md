# Result

| Item | Value |
|---|---|
| Date | 2026-11-18 |
| Challenger | `synthetic-challenger` |
| Challenged | `synthetic-challenged` |
| Settings | synthetic example |
| Operator | generator script |
| Control | yes |
| Seed SHA-256 | `b70b098ae55a7e2458cdf89f23fae55f7dfd58a957c18e5df8e93b160682a17f` |
| Verdict | superior |

## Superiority

```text
Superiority = candidate success - baseline success on the frontier quiz, in points.
code     n=10   baseline  10%  candidate  70%  superiority  +60 (95% CI +30 to +90)  solved 67% of baseline failures
plan     n=10   baseline   0%  candidate  80%  superiority  +80 (95% CI +50 to +100)  solved 80% of baseline failures
sat      n=10   baseline  10%  candidate  50%  superiority  +40 (95% CI +10 to +70)  solved 44% of baseline failures
OVERALL  n=30   baseline   7%  candidate  67%  superiority  +60 (95% CI +43 to +77)  solved 64% of baseline failures
VERDICT: candidate superior by 60 points (95% CI 43 to 77)
```

## Signal scan

```text
candidate:
Scanned 20 replies. Flagged 0 for auditor review.

baseline:
Scanned 2 replies. Flagged 0 for auditor review.
```

## README row

```markdown
| 2026-11-18 | `synthetic-challenger` | `synthetic-challenged` | synthetic example | generator script | yes | 7% | 67% | +60 | +43 to +77 | superior | 0 | [folder](runs/challenge-2026-11-18-synthetic-vs-synthetic/) |
```
