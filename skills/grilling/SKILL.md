---
name: grilling
description: Use when the user wants to stress-test an idea, plan, architecture, or decision
  through a critical interview, or says grill me. Routine implementation should proceed without
  this interview. For turning rough coding notes into a handoff brief use coding-agent-brief;
  for editing an existing prompt use prompt-refiner.
metadata:
  evaluation-status: unmeasured
---

## Scope and integration

Apply this skill to the requested target and task. User instructions and project
conventions take precedence; loading it does not authorize commits, pushes,
publishing, or unrelated changes.

Interview the user relentlessly until you reach a shared understanding. Map this as a **design tree**: every decision branches into the decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled: the questions you can ask _now_ without guessing at answers you haven't heard yet. Ask the whole frontier in one round: number each question and give your recommended answer. Then wait for the user's answers before the next round.

Format a round like so:

```
❓ **Q1** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

➡️ <your recommended answer>

---

❓ **Q2** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

➡️ <your recommended answer>
```

Each round the user answers reshapes the tree: settled decisions push the frontier outward and unblock questions that depended on them. Recompute the frontier and ask the next round. A question whose answer depends on another question still open in this round belongs to a _later_ round, not this one.

Finding _facts_ is your job, never the user's. When a frontier question needs a fact from the environment (filesystem, tools, etc.), look it up with available tools; delegate independent lookups only when delegation is available and authorized; don't ask the user for anything you could look up yourself. Don't block on it: a running exploration is an unsettled prerequisite, so only the questions downstream of it wait for the lookup to finish; ask the rest of the frontier now. The _decisions_ are the user's: put each to them and wait.

The session is done when the frontier is empty: every branch of the design tree visited, nothing left silently assumed. Summarize the settled decisions and unresolved points. The interview itself does not authorize implementation; proceed when the user requests that next step.
