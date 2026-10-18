# Coding outcome evaluations

The coding runner compares completed work rather than requiring a skill to load.
It is separate from `scripts/run-evals.py`, which evaluates routing and responses.
No instruction variant has been shown superior by this implementation.

## Local tasks

| Task | Requested change | Independent checks |
| --- | --- | --- |
| `retry-idempotence` | Cache successful operations by ID | No duplicate side effects, falsey results, independent IDs, retry after exceptions |
| `config-preservation` | Manage `retry_limit` without losing local settings | Nested key preservation, idempotence, unchanged malformed input, existing enabled setting |
| `parser-refactor` | Remove duplicate validation | Values, exception types/messages, evaluation order; readability requires manual review |

`evals/coding/tasks.json` defines the task prompts, snapshots, protected paths,
implementation paths, timeouts, and two check commands. All tasks use Python's
standard library. The first two baselines fail their new acceptance checks; the
working refactor baseline passes its behavior checks. Each reference patch must
pass all checks. This small Python sample does not represent all coding work.

Only `workspace/` is copied to the subject repository. Checks and reference
patches stay outside it. The evaluator runs checks independently with a clean
environment after the subject process ends. Editing a test inside the workspace
cannot replace the evaluator's checks. The checks still import subject code:
use trusted local fixtures, not adversarial submissions. File separation is not
a security boundary against a hostile process with access to the host.

## Describe first

These commands validate fixtures and print a planned matrix without starting a
runtime, checking credentials, creating result directories, or making API calls:

```bash
make coding-eval CODING_EVAL_ARGS='--agent claude --model SUBJECT_MODEL --task retry-idempotence --instructions baseline candidate none --repeats 2'
make coding-eval CODING_EVAL_ARGS='--agent codex --model SUBJECT_MODEL --task retry-idempotence --instructions baseline candidate none --repeats 2'
```

Replace `SUBJECT_MODEL` with an installed-runtime-supported model ID. Use
`--runtime /absolute/path/to/executable` to pin the executable. Omit `--task` to
select all three fixtures. The default is baseline instructions, two repeats.
Repeat two reverses variant order, giving baseline/candidate/none then
none/candidate/baseline. Do not compare different models as if only instructions
changed. The CLI does not set reasoning-effort options or estimate API prices.

## Isolation and execution

Execution requires explicit `--execute` after authorization for the model,
trial count, and spend controls. Do not put credentials in prompts or arguments.
The runner forwards only `ANTHROPIC_API_KEY` to Claude or `CODEX_API_KEY` to
Codex from an explicitly supplied environment. It never reads saved login files,
OAuth tokens, or local API-key helpers. `OPENAI_API_KEY` is not used for Codex
execution; credential provisioning belongs outside this tool.

Each trial gets a temporary Git repository, home, configuration roots, and copy
of the same skill inventory. Baseline/candidate instruction bytes are placed in
Claude's native user `CLAUDE.md` or Codex's native user `AGENTS.md`; none omits
that file. The task prompt stays unchanged. The runner does not install into
or modify the real home directory or this repository's active instruction file.

Claude runs with `dontAsk`, explicit coding tools, restricted file-tool scope,
its shell sandbox enabled with unsandboxed fallback disabled, disabled user
hooks, and empty MCP configuration. The copied skills are an additional allowed
working directory for their references. Codex uses workspace-write, never asks
for approvals, disables shell network access and ambient shell environment
inheritance, explicitly sets a temporary HOME/TMPDIR and standard executable
PATH for shell commands, and runs ephemerally. Temporary files stay within the
workspace so normal Python tempfile usage does not require broader write access. Neither adapter bypasses approvals/sandboxing.
Unsupported flags or denied necessary tools produce errors; do not relax
permissions to make a benchmark pass. Machine/admin policies and built-in
runtime behavior can still apply; record them during live calibration.

Claude's `--max-budget-usd` is forwarded as a per-session cap (default $1). It is
not a hard aggregate run cap. Codex has no dollar cap in this adapter: execution
requires `--supervised`, exactly one task/variant/repeat, and human supervision.
For example, only after budget authorization and explicit credential setup:

```bash
# Each is one paid trial. Choose real supported model IDs first.
make coding-eval CODING_EVAL_ARGS='--agent claude --model SUBJECT_MODEL --task retry-idempotence --instructions baseline --repeats 1 --max-budget-usd 1 --execute'
make coding-eval CODING_EVAL_ARGS='--agent codex --model SUBJECT_MODEL --task retry-idempotence --instructions baseline --repeats 1 --supervised --execute'
```

Use a distinct `--output-dir` for every invocation. The default is the ignored
`coding-eval-results/<timestamp>/`. The runner does not retry failed trials.
A runtime/verification error interrupts the remaining matrix; not-run trials
stay separate from skips and failures. Missing runtime or environment credential
is SKIP. A subject timeout or interruption kills its process group before
cleanup. Check timeouts are distinct from subject execution timeouts.

## Results and interpretation

Private `results.json` and `summary.md` retain the planned order, hashes of the
manifest/fixtures/skills/instructions, runtime version, requested and observed
model, transcripts, independent check results, changed paths and diff, protected
path violations, subject/verification latency, and available runtime usage/cost.
Credential values are redacted from saved output; verifier processes receive
none of the forwarded credentials. Workspaces are deleted after each trial.

PASS means the objective checks pass, the implementation changed, and no
protected path changed. FAIL means a failed check, missing implementation change,
or protected path violation. REVIEW means those automated requirements pass for
the refactor but readability still needs assessment. Unprotected extra edits are
flagged for scope review, not automatically classified as bugs. Runtime/protocol
or verifier-timeout problems are ERROR; unavailable prerequisites are SKIP.
A changed file is compared to the original snapshot, even if the subject commits
its work. Generated `__pycache__` and Git internals are excluded from the diff.

Missing usage, cost, model, skill loads, or native instruction-loading evidence
is null with an explanation. A staged native instruction file proves placement,
not model adherence. Codex JSONL does not provide a confirmed Skill-tool loading
record in this adapter; it is unknown, not an empty successful load list. No LLM
judge is called. Exit codes: 0 for PASS/REVIEW, 1 for objective failures, and 2
for errors, skips, invalid input, or a matrix stopped before all trials ran.

## Authorized 12-trial calibration

Use retry-idempotence, three instruction variants, two repeats, and two runtimes:
12 subject trials total. The first trial in each runtime doubles as its smoke
test; no additional billable probes or automatic retries are allocated. Keep
model/runtime/settings/skills/fixture constant within each runtime comparison.
Codex's six trials require six individually supervised invocations; retain the
planned order and results for each. Check failures count toward the allocation.
Abort if isolation, protocol, or spend controls fail. Additional trials need a
new budget decision. Report correctness/regressions before timing and costs;
12 calibration trials do not justify changing global defaults.

Offline verification:

```bash
python3 tests/test_coding_fixtures.py
python3 tests/test_run_coding_evals.py
make check
make ci
```

These use fake model runtimes and independent reference patches. They verify
orchestration, not live API compatibility or model performance. The repository's
existing agent configuration checks additionally run installed CLI validators
without requesting model completions. No live calibration has run.

Adapter flags/protocols were checked against installed Codex CLI 0.163.0 and
Claude Code 2.1.299 on 2026-10-18, and the official
[Codex automation documentation](https://developers.openai.com/codex/noninteractive),
[Claude CLI reference](https://code.claude.com/docs/en/cli-reference), and
[Claude sandbox documentation](https://code.claude.com/docs/en/sandboxing).
The runner checks required help flags at execution time, but a live trial is
still required before claiming end-to-end native runtime compatibility.
