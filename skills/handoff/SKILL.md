---
name: handoff
description: Use when the user asks to hand off, wrap up for, or summarize the current session so a fresh agent or new session can continue the work. Writes a handoff document outside the workspace. For improving an existing prompt draft use prompt-refiner.
argument-hint: "What will the next session be used for?"
metadata:
  evaluation-status: unmeasured
---

## Scope and integration

Apply this skill to the requested target and task. User instructions and project
conventions take precedence; loading it does not authorize commits, pushes,
publishing, or unrelated changes.

Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save to the temporary directory of the user's OS (`$TMPDIR`, else `/tmp`; `%TEMP%` on Windows) - not the current workspace. If the runtime provides a session scratchpad directory, use it instead. Tell the user the absolute path.

Include a "suggested skills" section in the document, naming which skills the next agent should load.

Do not duplicate content already captured in other artifacts (specs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.
