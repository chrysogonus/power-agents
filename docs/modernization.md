# First-phase modernization

## Status and scope

Closed on 2026-10-26. This phase repaired routing measurements and proposed a
shorter instruction candidate. The candidate was retired without live runs:
`instructions/general-global.md` was itself trimmed to non-default preferences,
leaving the candidate longer and out of date. The routing runner still accepts
any instruction file through `--instruction-file`; the coding runner compares
only baseline and none.

Implemented:

- Claude routing-runner instruction modes: baseline (default), none, and a
  custom file. Files load through the isolated user-wide `CLAUDE.md` path.
- Deterministic required/allowed/forbidden skill expectations alongside response
  judging, including successful handling without a skill.
- Natural prompts and explicit routing expectations for review, handoff/prompt,
  interview, and Ponytail boundaries; security-specific fixtures, explicit
  invocation, and no-skill cases. Distinct review prompts replace identical
  copies across the two review fixture sets.
- Instruction source hashes, isolation settings, and reported plugin metadata
  in schema-version-2 results. Existing per-trial response grades and skill
  hashes remain. Missing runtime/credentials still produce SKIP.

No paid runs or performance claims are part of this change.

Deferred: a coding-task benchmark, Codex evaluation adapter, project-scoped skill
installation, review-skill consolidation, changes to active skill descriptions,
and Grilling specification generation. Those need separate implementation and
validation; none is necessary to correct the current routing measurements.

Follow-up: the [coding-outcome runner](coding-evaluations.md) now implements the
offline harness and both adapters. Live results remain unmeasured. The deferred
list above records the original first-phase scope.

## Effective instruction environment

Before comparing live results, account for the entire instruction stack:

1. Host/system/developer instructions and platform approval/sandbox settings.
2. Global instructions, project and ancestor instruction files, and local rules.
3. Built-in skills, external plugins, and unmanaged skill descriptions.
4. Task prompt, explicit skill invocations, and references loaded during the run.

A concrete conflict observed during the 2026-10-18 review: external Superpowers
instructions require brainstorming before creative implementation and promote
skill loading even at marginal relevance. That can override an instruction
variant's intent that clear, small tasks proceed directly. These instructions
are outside this repository's managed inventory; this change does not alter
them.

In isolated routing runs, the environment is allowlisted, hooks are disabled,
MCP servers are empty, and the host's user configuration is not copied. Record
runtime-reported plugins from each trial; an absent field is unknown, not proof
that no plugins exist. Machine-level policies or bundled runtime instructions
may still apply. Treat these runs as measurements of the isolated setup, not a
complete reproduction of an interactive session.

## Comparison protocol

1. Use an isolated checkout/worktree. Installed files are symlinks into their
   source checkout: switching branches in that checkout or editing existing
   skills can change live configuration without running the installer.
2. Run offline checks first. Installer checks must use temporary HOME,
   CODEX_HOME, and CLAUDE_CONFIG_DIR paths, never the real home directory.
3. Obtain authorization for a total paid-run budget before live comparisons.
   Existing per-session caps do not bound the cost of a whole fixture matrix.
4. Select an explicit installed runtime, subject model, and judge model. Hold
   skill contents, fixtures, runtime version, and settings constant. Compare
   baseline, experimental, and no-instruction runs using repeated trials; vary
   run order to reduce time/order effects. Keep all structured results and hashes.
5. Inspect routing results separately from judge grades. Review individual
   failures and report sample sizes; a small difference is not proof of a win.
   A native instruction file on disk is not proof of model adherence: inspect
   live behavior before drawing conclusions about the instruction variants.
6. Before selecting a new default, compare a small representative set of actual
   coding tasks in isolated repositories with objective acceptance checks.
   Routing success alone does not establish correctness, autonomy, or speed.
   That coding-task harness is deferred; use explicitly supervised trials until
   it exists. Record outcomes, regressions, unnecessary changes, latency, and
   available usage separately. Mark missing measurements as unmeasured.

Opt-in commands, after budget authorization and environment-key setup:

```bash
make eval EVAL_ARGS='--instructions baseline --skill security-best-practices --model SUBJECT_MODEL --judge-model JUDGE_MODEL'
make eval EVAL_ARGS='--instructions none --skill security-best-practices --model SUBJECT_MODEL --judge-model JUDGE_MODEL'
```

`SUBJECT_MODEL` and `JUDGE_MODEL` are placeholders for runtime-supported model
IDs. Use `--instruction-file PATH` for additional instruction experiments.
Do not infer support for model-specific reasoning flags from generic guidance.

## Development workflow

| Situation | Workflow |
| --- | --- |
| Small fix with clear requirements | Implement, verify, report |
| Clear requirement, uncertain technical approach | Inspect, plan, implement, verify |
| Requirements need user decisions | Requested interview, settled requirements, then explicit implementation request |
| Large or risky change | Acceptance criteria, staged plan, verification |
| Unattended task | Explicit completion criteria and independent outcome checks |
| Code review | Choose the review skill by requested output |

For an implementation handoff, a durable specification can help substantial
work. Grilling currently ends with a conversational summary; automatic SPEC.md
creation is deferred. Exploratory discussions do not authorize implementation
or file creation. A fresh implementation session is optional.

A useful task prompt states the outcome, motivation, relevant context, hard
constraints, observable completion criteria, and decisions needing approval:

> Fix duplicate invoice export rows when retrying after a timeout. The current
> filters and permission checks must still apply. Inspect the existing export
> flow and add a regression check for retries. Finish when the focused tests and
> required project checks pass. Ask before changing the export API or adding a
> dependency.

## Guidance consulted

- [OpenAI skill documentation](https://developers.openai.com/codex/skills):
  progressive disclosure and focused activation descriptions.
- [OpenAI skill evaluations](https://developers.openai.com/blog/eval-skills):
  separate outcomes, process, style, and efficiency checks.
- [Claude instruction documentation](https://code.claude.com/docs/en/memory):
  native user instructions and concise, consistent guidance.

These sources support the approach; they do not establish that any instruction
variant is better than the baseline for any model.
