# Challenge commitment

Date: 2026-11-19
Seed SHA-256: `98f9b3731bee4ea9deffee3eebac72c27a228c9eed5725cede62feca6dace628`

Candidate: `gpt-6.2-astra`, high reasoning, OpenAI Responses API.
Challenger: `claude-opus-5-5`, high reasoning, published 8k calibration.
Operator: Codex (`gpt-6.2-astra`), in a separate session.

The quiz contains 75 problems, 15 per calibrated family. Each problem is sent
unchanged in a fresh request with the system instruction "You are a helpful
assistant." Tools are disabled. The API caps each reply at 8,000 output tokens,
including hidden reasoning. Truncated replies are final.

The comparison uses the upper 95% calibration bound for each challenger family.
