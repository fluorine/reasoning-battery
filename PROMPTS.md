# Prompts for contributors

Copy one of these lines into a coding agent that has a shell and `git` (for
example Claude Code). Replace the values in angle brackets. The agent reads the
linked instructions and does the work. It asks you before it spends model usage,
pushes anything or opens a pull request.

The repository is public. Check what the agent wants to publish before you say yes.

Every calibration and every challenge uses the same budget: 8,000 output tokens
per reply, hidden reasoning included. The agent sets it from the instructions, so
you do not add it to the prompt. The budget also limits the cost: a calibration is
at most 84 replies, and a challenge at most 105 replies per model.

## Prompt this to challenge a model

Test whether a model goes past the limit that a challenger admitted.

```text
Read https://github.com/fluorine/reasoning-battery/blob/main/runs/<calibration folder>/CHALLENGE.md and follow it as the operator. The challenged model is <MODEL ID>, with <REASONING SETTING>.
```

The current challengers and their calibration folders are in the Calibrations table
in the [README](README.md).

## Prompt this to check a published result

No model access needed. About 10 minutes.

```text
Read https://github.com/fluorine/reasoning-battery/blob/main/CONTRIBUTING.md, the "Rules for agents" and "1. Check a published result" sections, and run the check on runs/<result folder>. Show me the output, then offer to submit the VERIFICATIONS.md row as a pull request.
```

## Prompt this to repeat a test

Runs the published quiz again on the same models.

```text
Read https://github.com/fluorine/reasoning-battery/blob/main/CONTRIBUTING.md, the "Rules for agents" and "2. Replicate a result" sections, and replicate the result in runs/<result folder>. Estimate the usage cost and ask me before you send any prompt.
```

## Prompt this to audit replies for hidden signals

```text
Read https://github.com/fluorine/reasoning-battery/blob/main/CONTRIBUTING.md, the "Rules for agents" and "3. Audit replies for signals" sections, and audit the replies in runs/<result folder>. Quote anything that is not reasoning about the task or the answer line.
```

## Prompt this to benchmark a model

Gives the model a row in the benchmark leaderboard, and makes it a challenger that
others can challenge later. The model sees only the problems.

```text
Read https://github.com/fluorine/reasoning-battery/blob/main/CONTRIBUTING.md, the "Rules for agents" and "5. Benchmark a model or calibrate a new challenger" sections, and benchmark <MODEL ID> at <REASONING SETTING>. Add its rows to the Benchmark leaderboard and the Calibrations table. Estimate the usage cost and ask me before you send any prompt.
```

## Prompt this to write a challenge for another model

Your model finds its own limit, then challenges another model, or a fresh instance
of itself, to go past it. The calibration stays in the repository, so anyone can
challenge your model later.

```text
Read https://github.com/fluorine/reasoning-battery/blob/main/CONTRIBUTING.md, the "Rules for agents" and "5. Benchmark a model or calibrate a new challenger" sections, and calibrate <CHALLENGER MODEL ID> at <REASONING SETTING> as a new challenger. When its frontier.json and CHALLENGE.md are ready, follow that CHALLENGE.md as the operator to challenge <OTHER MODEL ID> with <ITS REASONING SETTING>. Estimate the usage cost and ask me before you send any prompt.
```

## Prompt this to make a new challenger only

Calibrates a model so that others can challenge it later. The natural candidate is
a model that just won a challenge.

```text
Read https://github.com/fluorine/reasoning-battery/blob/main/CONTRIBUTING.md, the "Rules for agents" and "5. Benchmark a model or calibrate a new challenger" sections, and calibrate <MODEL ID> at <REASONING SETTING> as a new challenger. Estimate the usage cost and ask me before you send any prompt.
```

## Prompt this to sharpen a calibration

```text
Read https://github.com/fluorine/reasoning-battery/blob/main/CONTRIBUTING.md, the "Rules for agents" and "6. Sharpen a calibration" sections, and add <N> more runs to runs/<calibration folder>. Estimate the usage cost and ask me before you send any prompt.
```

## Prompt this to add a runner for another provider

```text
Read https://github.com/fluorine/reasoning-battery/blob/main/CONTRIBUTING.md, the "Rules for agents" and "7. Add a runner" sections, and write tools/run-<provider>.ps1 for <PROVIDER> models. Test it on 3 prompts from a small quiz, then show me the result before you open a pull request.
```

## Prompt this to propose a new task family

```text
Read https://github.com/fluorine/reasoning-battery/blob/main/CONTRIBUTING.md, the "Rules for agents" and "8. Propose a new task family" sections, and Families.cs. Design a new family that tests <CAPACITY>. Show me the design before you write code, and do not publish it until I decide whether to keep it private.
```

## Prompt this to report a problem

```text
Read https://github.com/fluorine/reasoning-battery/blob/main/CONTRIBUTING.md, the "9. Report a problem" section. The problem is: <WHAT YOU SAW>. Reproduce it with the commands there, then draft the issue for me to review.
```
