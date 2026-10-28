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
| `pagination-bounds` | Return 1-based pages with metadata | Last partial and exactly full pages, past the end, empty input, rejected zero, negative, bool, and float arguments |
| `csv-export` | Spreadsheet-safe CSV | Quoting, CRLF, `None`, formula-injection prefixes for text but not numbers, empty input |

`evals/coding/tasks.json` defines the task prompts, snapshots, protected paths,
implementation paths, timeouts, two check commands, a reference patch, and two
booleans: `manual_review` (the trial ends as REVIEW instead of PASS) and
`baseline_acceptance` (whether the unchanged snapshot passes its acceptance
check, asserted by the fixture tests). All tasks use Python's
standard library. Every baseline except the working refactor fails its new
acceptance checks; the refactor baseline passes its behavior checks. The last
two tasks hide easy-to-miss edge cases in otherwise simple requests, where a
verification pass has something to find. Each reference patch must
pass all checks. This small Python sample does not represent all coding work.

Only `workspace/` is copied to the subject repository. Checks and reference
patches stay outside it. The evaluator runs checks independently with a clean
environment after the subject process ends. Editing a test inside the workspace
cannot replace the evaluator's checks. The checks still import subject code:
use trusted local fixtures, not adversarial submissions. File separation is not
a security boundary against a hostile process with access to the host.

## Describe first

These commands validate fixtures and print a planned matrix without starting a
runtime, creating result directories, or making API calls. The plan records
which credential variable is set, by name only; values are never read:

```bash
make coding-eval CODING_EVAL_ARGS='--agent claude --model SUBJECT_MODEL --task retry-idempotence --instructions baseline none --repeats 2'
make coding-eval CODING_EVAL_ARGS='--agent codex --model SUBJECT_MODEL --task retry-idempotence --instructions baseline none --repeats 2'
```

Replace `SUBJECT_MODEL` with an installed-runtime-supported model ID. Use
`--runtime /absolute/path/to/executable` to pin the executable. Omit `--task` to
select all five fixtures. `--timeout SECONDS` overrides every task's subject
timeout, and `--manifest PATH` reads a different task manifest.
`python3 scripts/run-coding-evals.py --help` lists all options. The default is baseline instructions, two repeats.
Repeat two reverses variant order, giving baseline/none then none/baseline.
Do not compare different models as if only instructions changed. The CLI does
not set reasoning-effort options or estimate API prices.

## Verify gate on or off

`--gate off on` crosses each instruction variant with and without the
[verify gate](verify-gate.md), and alternates their order between repeats like
the instruction variants. With `on`, the trial copies `hooks/verify-gate.py`
next to the workspace and stages its hooks in the trial's `settings.json`
instead of `disableAllHooks`. The gate's state stays in the trial's home, so
there is no cross-review, project check, or experiment: only the self-check
runs. Each trial saves the gate's log records as `gate_log`, the report keeps
the script's hash as `gate_sha256`, and `summary.md` counts passed, failed,
and pending-review trials per gate setting. A gate-on trial whose log lacks
the gate's verification is an ERROR, so it never enters the comparison as a
pass. Only Claude is supported, because Codex skips hooks until they are
trusted interactively. The first live trial must confirm that Claude runs
Stop hooks in `--print` mode.

## Isolation and execution

Execution requires explicit `--execute` after authorization for the model,
trial count, and spend controls. Do not put credentials in prompts or arguments.
The runner forwards only `ANTHROPIC_API_KEY` and `CLAUDE_CODE_OAUTH_TOKEN` (from
`claude setup-token`, billed to the subscription) to Claude, or `CODEX_API_KEY` to
Codex, from an explicitly supplied environment. When both Claude variables are
set, both are forwarded and the API key outranks the token, as in Claude itself;
the report names only the first one set. With a subscription token, `--max-budget-usd` applies to
Claude's estimated cost, not to billing. It never reads saved login files or
local API-key helpers. `OPENAI_API_KEY` is not used for Codex
execution; credential provisioning belongs outside this tool.

Codex can instead use a separate ChatGPT login in a dedicated directory, created
once with `CODEX_HOME=/absolute/eval/home codex login --device-auth` and passed
as `--codex-home /absolute/eval/home`. Never point it at the everyday `~/.codex`.
Preflight checks `codex login status` and refuses a directory containing
instructions, configuration, skills, rules, plugins, or memories, except the
bundled `skills/.system` and plugin caches Codex recreates itself. Each trial
stages `config.toml` and the instruction variant there and removes both
afterwards. Codex itself reads and refreshes the login; the runner does not.
Codex-owned logs, caches, and login refreshes persist between trials. A ChatGPT
login syncs account plugins and apps, so the staged configuration disables the
`plugins`, `remote_plugin`, and `apps` features in every Codex trial.

Each trial gets a temporary Git repository, home, configuration roots, and copy
of the same skill inventory. Baseline instruction bytes are placed in
Claude's native user `CLAUDE.md` or Codex's native user `AGENTS.md`; none omits
that file. The task prompt stays unchanged. The runner does not install into
or modify the real home directory or this repository's active instruction file.

Claude runs with `dontAsk`, explicit coding tools, its shell sandbox enabled
with unsandboxed fallback disabled, disabled user hooks, and empty MCP
configuration. `sandbox.failIfUnavailable` makes Claude exit at startup when the
sandbox cannot run (on Linux/WSL2 it needs `bubblewrap` and `socat`); without it,
Claude 2.1.299 silently runs commands unsandboxed. The adapter does not use
`--restricted`: on 2.1.299 it also suppresses the user `CLAUDE.md` and user
skills, so every instruction variant would behave like `none`. Instead,
`permissions.blockReadsOutsideWorkingDirectories` fences file reads, and the only
allow rules are `Bash`, `Skill`, and `Edit(//<workspace>/**)`, so `dontAsk`
denies edits elsewhere. Before each subject run, a credential-free local
`/context` call must report exactly the staged `CLAUDE.md` (none for `none`) and
the staged user skills; otherwise the trial is an ERROR and no model call is
made. Its report is recorded as `instruction_loading`. The copied skills stay
readable under the read block without `--add-dir`; adding them would make them
writable to sandboxed commands and, on Linux, makes every sandboxed command fail
because the directory sits under the protected `.claude/skills` path. Codex uses workspace-write, never asks
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
`coding-eval-results/<nanosecond timestamp>/`. The runner does not retry failed trials.
A runtime/verification error interrupts the remaining matrix; not-run trials
stay separate from skips and failures. Missing runtime or environment credential
is SKIP. A subject timeout or interruption kills its process group before
cleanup. Check timeouts are distinct from subject execution timeouts.

## Results and interpretation

Private `results.json` (schema version 1) retains the planned order, hashes of
the manifest/fixtures/skills/instructions, runtime version, requested and
observed model, transcripts, independent check results, changed paths and diff,
protected path violations, subject/verification latency, and available runtime
usage/cost. `summary.md` holds only two tables: each trial's task, instructions,
gate, status, subject seconds, and scope review, and the per-gate counts.
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
not model adherence. `isolation.native_instruction_loading_confirmed` is true
only when Claude's `/context` matched the staged files in every trial. Claude trials also save a redacted, owner-only
`trial-N-claude-debug.log` and list its `CLAUDE.md` lines as
`claude_md_debug_lines` for manual review of native loading; other secrets in
that log are not pattern-matched. Codex JSONL does not provide a confirmed Skill-tool loading
record in this adapter; it is unknown, not an empty successful load list. No LLM
judge is called. Exit codes: 0 for PASS/REVIEW, 1 for objective failures, and 2
for errors, skips, invalid input, or a matrix stopped before all trials ran.

## Authorized calibration

Use retry-idempotence, both instruction variants, two repeats, and two runtimes:
8 subject trials total. The first trial in each runtime doubles as its smoke
test; no additional billable probes or automatic retries are allocated. Keep
model/runtime/settings/skills/fixture constant within each runtime comparison.
Codex's four trials require four individually supervised invocations; retain the
planned order and results for each. Check failures count toward the allocation.
Abort if isolation, protocol, or spend controls fail. Additional trials need a
new budget decision. Report correctness/regressions before timing and costs;
8 calibration trials do not justify changing global defaults.

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
