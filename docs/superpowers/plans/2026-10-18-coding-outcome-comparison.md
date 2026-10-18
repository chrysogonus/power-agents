# Coding Outcome Comparison Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax. Default to inline execution; delegation requires separate authorization. The user authorized offline implementation on 2026-10-18; live evaluations still require separate authorization.

**Starting point:** Signed commit `8728874` on `modernization/eval-first`. The first-phase runner and instruction candidate are committed; this plan is a separate, uncommitted deliverable.

**Goal:** Make a small, reproducible comparison of baseline, candidate, and no-global-instruction configurations on actual coding tasks in Claude Code and Codex.

**Architecture:** Keep the existing routing runner separate. Add one Python CLI that stages fresh fixture repositories, invokes a runtime-specific adapter, runs independent acceptance checks, and writes structured results. Begin with three local tasks and offline fake runtimes; authorize a small live calibration separately before expanding the matrix.

**Tech Stack:** Python 3 standard library, Git, existing Claude Code/Codex executables, unittest; no new external dependencies.

**Spec:** [First-phase report and comparison protocol](../../modernization.md). This plan implements the next measurement step, not every deferred modernization workstream.

## Global constraints

- Preserve the installed baseline, existing skill entrypoints, and global installer behavior.
- Work in an isolated worktree. Do not run installation against the real home directory.
- Keep paid runs opt-in and excluded from ordinary tests and CI. Do not read personal credential files or reuse host configuration.
- Do not commit or push during implementation unless authorized for that work.
- Do not switch global defaults based on fake-runtime results or routing scores.
- Configure runtime executable and model explicitly. Verify supported flags against the installed runtime before execution; do not assume identical effort or cost controls.
- Compare instruction variants within each runtime/model first. Results do not isolate model quality from runtime behavior.

## Review focus

Each condition below has an owning task and regression test:

1. An agent changes its own tests or exits early: independent acceptance checks must still detect incomplete work (Task 1/3).
2. A runtime is missing, incompatible, or unauthenticated: report SKIP or ERROR, never a successful trial (Task 2).
3. A timed-out process leaves descendants running: terminate the process group before cleanup (Task 2).
4. A trial changes unrelated files or deletes a protected file: retain the diff and flag the scope violation (Task 3).
5. Usage, cost, or skill-loading metadata is absent: report unknown rather than zero or successful non-activation (Task 3).

## Task 1: Build three independently verifiable task fixtures

**Files:**
- Create: `evals/coding/tasks.json`
- Create: `evals/coding/retry-idempotence/`, `evals/coding/config-preservation/`, `evals/coding/parser-refactor/`
- Create: `tests/test_coding_fixtures.py`
- Modify: `tests/run.sh` to run the offline fixture tests.

**Interfaces:**
- A manifest task contains `id`, `snapshot`, `prompt`, `verification`, `protected_paths`, `timeout_seconds`, and `verification_timeout_seconds`.
- Paths are repository-relative and cannot escape the fixture root. Verification is an argv array executed without a shell, not a command supplied by the agent.
- Each task directory has `workspace/`, `checks/`, and `reference.patch`. Copy only `workspace/` into the agent's repository. Keep checks and the reference patch outside it.
- Checks consume the workspace path and exit zero only when the task's acceptance criteria hold. These checks are withheld evaluation artifacts, not a claim of protection against a deliberately adversarial local process.

- [x] Write `test_coding_fixtures.py` cases that reject invalid paths, missing commands, duplicate IDs, and nonpositive/nonfinite timeouts.
- [x] Add retry-idempotence: fix a synchronous Python helper so retrying the same operation ID returns its prior successful result without repeating a side effect; distinct IDs still run separately. Check falsey cached results and that failed operations can be retried. Concurrency and persistence are excluded. The supplied baseline must fail the withheld regression check.
- [x] Add config-preservation: extend a small Python JSON settings reconciler with one requested managed field while preserving unknown nested keys and rejecting malformed input without overwriting the file. Check repeated reconciliation produces the same result. The fixture prompt must name the field, its value, and its ownership boundary. The baseline must fail the new-field check.
- [x] Add parser-refactor: remove duplication in a working Python parser while preserving values, exception types, and evaluation order. Require a changed implementation plus independent behavior checks; assess readability and unnecessary abstractions manually rather than pretending tests prove maintainability.
- [x] For every task, test that the baseline has the declared initial status and applying its reference patch passes every check. Verify the fixtures need no network, dependencies, credentials, or machine-local files.
- [x] Run `python3 tests/test_coding_fixtures.py`; expect all fixture-integrity tests to pass. Document that these tasks are an initial sample, not broad evidence across stacks.

## Task 2: Add isolated native-runtime execution

**Files:**
- Create: `scripts/run-coding-evals.py`
- Create: `tests/fixtures/fake-codex.py`
- Create: `tests/fixtures/fake-coding-claude.py`
- Create: `tests/test_run_coding_evals.py`
- Modify: `tests/run.sh` to include the new offline runner tests.

**Interfaces:**
- `load_tasks(manifest: Path, selected: str | None) -> list[dict]`
- `stage_trial(task: dict, trial_root: Path, agent: str, instruction_file: Path | None, skills_root: Path) -> Path`: return the fresh Git workspace path.
- `run_subject(agent: str, executable: str, model: str, task: dict, workspace: Path, trial_root: Path) -> dict`: return status, redacted transcript, elapsed seconds, observed usage/cost/skills or null, and error details.
- CLI: `--agent claude|codex`, `--runtime PATH`, `--model ID`, `--task ID`, `--instructions baseline candidate none` (one or more named variants), `--repeats N`, `--output-dir PATH`. The default variant is baseline and the default repeat count is two. Omit `--task` to select all three tasks. Default to describing the trial matrix; only `--execute` starts runtime sessions.
- Use the existing global instruction source files. Stage Claude's native user `CLAUDE.md` and Codex's native user `AGENTS.md` in isolated configuration roots; install identical skill snapshots into each runtime's documented discovery location.

- [x] Write fake-runtime tests proving describe-only mode never invokes a model, instruction variants use native files with exact hashes, the prompt stays unchanged, and personal configuration/env markers do not propagate.
- [x] Test missing runtime/auth as SKIP; unsupported flags and malformed protocol as ERROR; denied necessary tools as ERROR; timeout and interrupt cleanup including descendants. Missing required credentials are detected without printing them.
- [x] Implement the CLI and adapters using the smallest standard-library subprocess/environment handling. Keep the routing runner unchanged; avoid extracting a shared framework before actual duplication warrants it.
- [x] Before implementing each adapter's argv/protocol, inspect its installed CLI help and current official native configuration/automation documentation. Record executable/version/model and relevant capability checks in results. A fake-runtime pass alone does not prove adapter compatibility.
- [x] Permit the filesystem and command tools needed for the fixture within its isolated workspace. Use supported sandbox/approval controls; do not bypass permissions or inherit hooks/MCP/plugins to make a run pass.
- [x] Forward only an explicitly provided runtime-specific environment credential. Use the OpenAI credential workflow before any real OpenAI-backed test; do not auto-provision or copy credentials during offline implementation.
- [x] Run `python3 tests/test_run_coding_evals.py`; expect both adapter simulations and all error/cleanup cases to pass without paid calls.

## Task 3: Score outcomes and expose a bounded comparison command

**Files:**
- Modify: `scripts/run-coding-evals.py`, `tests/test_run_coding_evals.py`
- Modify: `Makefile`, `tests/run.sh` (including the existing Make-target contract test), `README.md`, `.gitignore`

**Interfaces:**
- `verify_trial(task: dict, workspace: Path, trial_root: Path) -> dict`: run trusted checks from outside the agent workspace with credentials removed; record their exit status and timeout separately from runtime status.
- `write_results(output: Path, report: dict) -> None`: write private `results.json` and `summary.md` without overwriting an existing directory.
- Result records include task/source/instruction/skill hashes, requested/actual runtime and model, trial status, verification status, protected-path changes, full diff including untracked files, elapsed time, available usage/cost, observed skill loads, and missing-measurement explanations.
- Add `make coding-eval CODING_EVAL_ARGS='...'`. No live evaluation is a dependency of `make test`, `make check`, or `make ci`.

- [x] Write tests where the fake agent prints success but leaves the bug, edits its own tests, changes protected files, returns early, or produces no usage/skill metadata. None may become a clean successful result merely because the runtime exited zero.
- [x] Implement objective outcome scoring and preserve separate scope flags and manual maintainability assessment. Report acceptance-check pass, regression-check pass, and protected-path violations separately. The refactor requires a nonempty implementation diff; behavior checks alone cannot establish that cleanup was accomplished. Until its readability requirement is reviewed, mark that dimension as pending manual review. A small diff is not inherently more correct; an extra edit is not automatically a defect.
- [x] Add secret-redaction tests for both runtime credentials, error output, transcripts, summaries, and verifier environments. Validate cleanup and private result-directory permissions.
- [x] Add a describe-only test showing exactly three variants, three tasks, and a caller-selected repeat count for one runtime/model. Explicitly record trial order; hold fixtures and skills constant across variants.
- [x] Document per-runtime spend controls actually available. Never advertise a hard total dollar cap if the runtime cannot enforce one. Missing price/usage data stays unknown; unsupported cost controls require supervised single-trial execution instead of unattended scheduling.
- [x] Run both new test files, `make check`, and `make ci`. Expect all checks to pass with no paid calls and with temporary installer environments only.

## Task 4: Calibrate with a small authorized live comparison

**Files:**
- Create after measurements: `docs/coding-evaluation-results.md`
- Keep raw private/redacted run artifacts in a gitignored directory.

- [ ] First obtain authorization for explicit runtime/model IDs, trial count, and spend controls/budget. Offline implementation authorization does not authorize these calls.
- [ ] Use retry-idempotence for calibration. Validate its baseline and reference fix offline, then treat the first authorized trial in each runtime as its smoke test of native instruction loading and necessary tools. These are part of the 12-trial allocation, not additional paid calls. Abort expansion on isolation/protocol/cost-control problems.
- [ ] Start with one task, three instruction variants, two repeats, and two runtimes: 12 coding trials, no LLM judge. This is calibration, not enough evidence to select a winner. Balance variant order and keep runtime/model/settings fixed within comparisons.
- [ ] Inspect traces and artifacts for premature stopping, unnecessary clarification, incorrect native loading, and unexpected external instructions. Record unknowns and failures rather than excluding inconvenient trials.
- [ ] Stop at 12 allocated subject trials, including failures; do not silently retry or replace failed trials. A larger 54-trial comparison across three tasks is a possible later phase requiring a new decision and budget authorization. Do not run a separate routing matrix automatically.
- [ ] Report correctness and regressions first, then scope/maintainability observations, latency, and available cost. Publish sample sizes, failures, and uncertainty; do not claim a universal best configuration from this sample.
- [ ] Recommend retaining the baseline unless evidence supports a deliberate change. Any default selection or external plugin change is a separately authorized action, not an automatic harness feature.

## Calibration allocation and report

| Runtime | Task | Variants | Repeats per variant | Subject trials |
| --- | --- | --- | --- | --- |
| Claude Code | retry-idempotence | baseline, candidate, none | 2 | 6 |
| Codex | retry-idempotence | baseline, candidate, none | 2 | 6 |
| Total | | | | 12 |

For each runtime, schedule baseline/candidate/none for repeat one and
none/candidate/baseline for repeat two. No LLM judge is used. Hold the prompt,
fixture, skill snapshot, model, timeout, and runtime settings constant; only the
global instruction variant changes. Store the planned matrix before execution
and record scheduled, started, completed, failed, and skipped trials separately.
No extra billable probes or retries are included in this allocation.

The report must answer:

- Which trials satisfy the independent acceptance and regression checks?
- Which make protected or apparently unrelated edits? Include the diff and any
  manual assessment rather than using line count as a proxy for quality.
- How long do subject execution and independent verification take separately?
- What token usage and cost did the runtime report? Mark missing figures as
  unknown; label any price-based estimate with its source and assumptions.
- Does runtime telemetry establish skill loading or native instruction loading?
  Separate confirmed observations from incomplete traces and inferred behavior.

The calibration verifies the measurement path. It cannot establish broad model
rankings or justify selecting a global default from two repeats on one task.

## Completion criteria and exclusions

Offline implementation is recorded in [the runner documentation](../../coding-evaluations.md).
Task 4 remains unexecuted and budget-gated.

The offline portion is complete when all three fixtures validate, both adapters
pass fake-runtime orchestration tests, objective checks catch fake success,
missing measurements stay explicit, and repository checks pass. Live results
remain unmeasured until Task 4 is authorized and executed.

Project-level installation, Grilling/SPEC behavior, review consolidation,
independent Ponytail ablations, and additional stack benchmarks remain outside
this phase. No new global default is selected by this plan.
