# Development and Evaluations

This page covers working on the repository itself: running the checks, adding
skills, and measuring skill and instruction behavior with paid evaluations. The
required workflow is summarized in [Contributing](../CONTRIBUTING.md).

## Quality Checks

The core local checks use Make, Bash, Git, `jq`, Python 3 with `tomlkit` and
PyYAML, and [ShellCheck](https://www.shellcheck.net/). The
[README](../README.md#quality-checks) lists the install command for Debian or
Ubuntu.

Run the complete pipeline locally after committing and before pushing:

```bash
make ci
```

`make ci` runs the checks once against the current working tree and once against
a source archive of `HEAD`. During development, use `make check` to run only the
faster working-tree pass.

The checks parse and statically analyze every repository shell script, validate
skill metadata, exercise settings reconciliation and the installer under
temporary isolated home directories, check the status-line output, and reject
whitespace errors or unresolved conflict markers. If `codex` is installed, the
tests ask it to parse the managed TUI configuration and evaluate every authored
command rule. If `claude` is installed, the tests run `claude doctor` against an
isolated installed configuration and reject any invalid-settings report. Both
checks also feed their runtime a known-invalid setting to prove that the
validation path is active. The Claude check also covers the installed hook
entries. Codex has no non-interactive command that parses `hooks.json`, so the
Codex hook entries are checked only by the repository's own tests. A missing
local runtime is reported as `SKIP`, never `PASS`. GitHub Actions installs the
current npm releases of both agents and requires both compatibility checks; use
`POWER_AGENTS_REQUIRE_AGENT_RUNTIMES=1 make ci` for the same requirement locally.

`make check` works from either a Git checkout or an exported source archive
without `.git`; `make ci` requires a Git checkout. Installer and agent-runtime
tests never use the invoking user's live configuration. `jq` is an installer and
status-line runtime dependency, and ShellCheck is used for static analysis at warning-or-higher severity.

## Adding or Updating a Skill

See the [skills documentation](../skills/README.md) for the current inventory and
skill format. Each skill must live at `skills/<skill-name>/SKILL.md`, and its
frontmatter `name` must exactly match the directory name. Rerun `./install.sh`
after adding a skill so both agents receive its per-skill link. Edits to an
already linked skill are available immediately.

Use the runtime's built-in review (`/review` in Codex, `/code-review` in Claude
Code) for general code reviews. Use `review-report` when findings should be
written to a file, explained for a reader without codebase context, or provided
as paste-ready review comments. Its routing fixtures in `evals/evals.json` cover
both sides of that boundary; the checks validate their schema, but do not
execute agent sessions or measure routing pass rates. Run the opt-in evaluations
below to measure their behavior.

The [agent skills research catalog](../research/agent-skills-2026-10-05.md)
records upstream candidates, sources, and integration notes. Ten selected skills
are included in the [imported skill inventory](../skills/README.md#imported-skills);
their live routing and task-effect evaluations remain unmeasured.

## Behavioral Skill Evaluations

`make eval` runs every case in `skills/*/evals/evals.json` using Claude Code and
grades every assertion in a separate Claude session. This uses paid Anthropic
API calls and is deliberately excluded from `make check` and `make ci`; those
commands test the runner against a fake runtime with no network or credentials.
The runner uses Python 3 and the repository's existing PyYAML dependency.

Set `ANTHROPIC_API_KEY` in your environment without putting it in a command or
file in this repository. For example, in Bash:

```bash
read -rsp 'Anthropic API key: ' ANTHROPIC_API_KEY
printf '\n'
export ANTHROPIC_API_KEY
make eval
unset ANTHROPIC_API_KEY
```

To limit the fixture set or change the defaults:

```bash
make eval EVAL_ARGS='--skill review-report --repeats 5 --threshold 0.8'
```

Select instructions explicitly when comparing variants (each command makes paid
API calls; run only with an authorized budget):

```bash
make eval EVAL_ARGS='--instructions baseline --skill security-best-practices'
make eval EVAL_ARGS='--instructions candidate --skill security-best-practices'
make eval EVAL_ARGS='--instructions none --skill security-best-practices'
# Or use --instruction-file /absolute/path/to/experimental.md
```

The default is **baseline**; use `--instructions none` to reproduce the old
runner's absence of global instructions. The candidate is experimental and is
not installed by `make install`. These are routing/response evaluations with
only the Skill tool: they do not establish coding quality or prove runtime
instruction loading through fake-runtime tests. See the
[first-phase change report and comparison protocol](modernization.md).

### Isolation, grading, and runtime details

All repository skills remain installed during a filtered run, so routing can
select a different skill. Each trial starts with a temporary home, config root,
and working directory. By default, the baseline `instructions/general-global.md`
is copied to the isolated Claude user-wide `CLAUDE.md`; instruction text is never
inserted into the task prompt. It loads no live user configuration or credentials;
only `ANTHROPIC_API_KEY` is forwarded. Cases get the Skill tool only; this first
runner supports the repository's prompt-only fixture sets. File fixtures
produce an explicit error. The judge has its own empty config and no tools; it
treats prompts, expected outputs, assertions, and transcripts as untrusted data.

The default is five trials per case and an 80% minimum pass rate. A trial passes
when explicit routing expectations and every assertion pass. A fixture with
`"routing": {"allowed": []}` can pass without loading a skill. Legacy fixtures
without routing expectations still require a repository skill load.
Skill loading is observed through matching Skill calls and successful tool
results, rather than the agent's statements. Judge evidence must quote the
observed response or load record. Required, allowed, and forbidden skills are
checked deterministically, independently of the judge. Failed assertions or
routing mismatches count as failed trials. Runtime, protocol, or judge errors
invalidate the run even if the remaining trials reach the threshold. A missing
runtime or environment key reports `SKIP`; it never reports `PASS`.

Results go to the gitignored `eval-results/<run-id>/results.json` and `summary.md`,
including per-case pass rates, each assertion's grade and evidence, redacted
runtime transcripts, actual model names, runtime version, source-file hashes,
instruction variant/path/hash, and configured isolation settings. Schema version
2 adds deterministic routing results and runtime-reported plugin metadata
(`null` when the runtime does not report it). The judge never receives the global
instruction file. Exit codes are 0 for passing cases, 1 for a case below
threshold, and 2 for `SKIP`, operational errors, or invalid arguments. Result
directories are private and an existing result directory is never overwritten.

CLI flags were checked against Claude Code 2.1.226's help and installed protocol.
The runner also checks required flags before a credentialed run. It uses normal
headless mode to preserve automatic skill discovery, restricts setting sources
to its isolated user config, disables hooks, and supplies an empty MCP config.
Sessions have a 180-second timeout and a $1 API budget cap each. Use `--model`,
`--judge-model`, `--timeout`, `--runtime`, or `--output-dir` through `EVAL_ARGS`
when needed; `python3 scripts/run-evals.py --help` lists all options. Codex is not
supported as an evaluation runtime yet.

## Coding Outcome Evaluations

A separate [coding runner](coding-evaluations.md) evaluates retry idempotence,
settings preservation, and a parser refactor using independent acceptance and
regression checks. It supports isolated Claude Code and Codex adapters and
baseline/candidate/no-instruction comparisons. By default it only describes the
planned trials:

```bash
make coding-eval CODING_EVAL_ARGS='--agent claude --model SUBJECT_MODEL --task retry-idempotence --instructions baseline candidate none --repeats 2'
```

Replace the model placeholder before execution. Offline fake-runtime tests run
in ordinary checks; live calls require separate model/budget authorization and
`--execute`. Codex execution is limited to one supervised trial at a time because
this adapter has no dollar cap. No paid calibration has run and no new global
default has been selected. See the
[12-trial protocol](coding-evaluations.md#authorized-12-trial-calibration).
