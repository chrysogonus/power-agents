# Verify Gate and Cross-Review

The verify gate is this repository's core: `make install` always installs it,
with or without the [optional components](installation.md#choosing-components).
Both agents run [`hooks/verify-gate.py`](../hooks/verify-gate.py) on
`UserPromptSubmit` and `Stop`, which the installed hook entries allow 30 and
600 seconds. A turn qualifies when it changed files, or when the final answer
is at least 600 characters and does not end in a question.
Changes include edits to untracked files and commits made during the turn.
A turn that only commits work the gate already checked, or amends a commit
message, does not count: every file must still be as it was when the most
recent checked turn ended in this session, and new commits must hold exactly
that content. Otherwise, staging a file also counts as a change.

Outside a git repository the gate cannot see changes, so only long answers
qualify there. If the gate has no snapshot from the start of the turn, for
example because it was installed mid-session, any uncommitted file counts as
changed.

- **Self-verification** (on by default): the first `Stop` of a qualifying turn
  sends the agent back once to check its answer against files, tests, or docs.
  If the repository has a [check command](#per-project-settings), the gate runs
  it first and adds the result to that prompt.
- **Cross-review** (off by default): at that same `Stop`, the *other* agent
  starts in the background, runs read-only, and reviews while the agent
  verifies. It receives the latest user request, the session transcript, and
  the diff of this turn's changes, including commits and the contents of new
  untracked files. Files that were already modified before the turn and that
  the turn did not touch are listed separately, not diffed. Files that were
  already modified and that the turn edited again are diffed in full, with a
  note that the diff includes the earlier edits. The reviewer starts before the
  [check command](#per-project-settings) runs, so it never sees the check's
  result. By default only turns that changed files are reviewed. At the next
  `Stop`, the gate waits for the review. If the reviewer reports no material
  issues, the turn ends with a notice. Otherwise the
  feedback is returned as "Here is feedback from another coding agent. What do
  you think about this?" The agent is asked to accept or reject each point
  and to end with its final answer, or "Final answer unchanged.", followed
  by "Open items:" when points it rejected, claims it could not verify, or
  unfinished work remain. A missing,
  failing, or timed-out reviewer is skipped with a notice; it never blocks the
  turn. A new prompt stops a review that is still running.
- **Summary**: a checked turn ends with one line from the gate itself, for
  example `verify gate · check failed with exit code 1 (14s) · self-check
  fixed, edited files · cross-review (Codex): accepted 2, rejected 1 · 1 open
  item`. It reports what the passes said and whether they changed files, not
  whether they were right. The project check in it ran before the self-check.
  The open-item count comes from the last pass's "Open items:" section, which
  the agent is asked to include only when something is left open. See
  [The summary line](#the-summary-line) for every variant.

## Controls

| Control | Effect |
| --- | --- |
| `python3 ~/.agents/hooks/verify-gate.py cross-review on\|off\|status` | Persistently toggles cross-review through `~/.config/power-agents/cross-review-on`. `status` reports only this file, not `CROSS_REVIEW` or a project's `cross_review`. |
| `python3 ~/.agents/hooks/verify-gate.py doctor` | Checks that `~/.agents/hooks/verify-gate.py` exists, that both agents' hook entries run the gate (honoring `CLAUDE_CONFIG_DIR` and `CODEX_HOME`; a missing agent folder is only a warning), that the state directory is writable (creating it if needed), and that `projects.json` and `experiment.json` are valid. When cross-review is on globally or for any project, it also requires both reviewer CLIs on PATH and checks that the Codex reviewer's MCP servers can be disabled. Exits 1 if a required check fails. |
| `python3 ~/.agents/hooks/verify-gate.py review --agent claude\|codex [--base REF] [--focus TEXT]` | Runs a review now, outside the gate, and prints it. With `--agent` the *other* agent reviews; name the reviewer directly with `--reviewer`. Run it inside a git repository: it reviews that repository's uncommitted and untracked changes, or with `--base` also the commits since the merge base with `REF`, clipped to 40,000 characters. `--focus` tells the reviewer what to concentrate on. No transcript is sent; the reviewer runs with the same restrictions as in the gate. It ignores the cross-review toggle and project settings, so the diff always goes to the reviewer's vendor. Exits 0 on success, 1 if the review failed, 2 on bad arguments, and 130 when interrupted. |
| `python3 ~/.agents/hooks/verify-gate.py export [--since DAYS] [--anonymize] [--capture]` | Prints one CSV row per checked turn, or with `--capture` the captured texts for labeling. See [Measuring the verify gate](experiment.md). |
| `python3 ~/.agents/hooks/verify-gate.py status` | Lists the gate's background reviews that are still running, one line per session state file. Manual `review` runs and experiment audits are not listed. |
| `python3 ~/.agents/hooks/verify-gate.py cancel [SESSION]` | Stops the gate's running background reviews, or only one session's; `SESSION` is the name `status` prints. The gate then skips the review with a notice. |
| `CROSS_REVIEW=1` or `CROSS_REVIEW=0` | Forces cross-review on or off for sessions started with it. |
| `CROSS_REVIEW_SCOPE=changes` | Set to `all` to also cross-review long answers from turns that changed no files. |
| `VERIFY_GATE=0` | Disables the gate, including cross-review, for sessions started with it. The commands above still work. |
| `VERIFY_GATE_MIN_CHARS=600` | Sets the answer length that makes a turn qualify. When set, it overrides a project's `min_chars`, and a value that is not a number means 600. |
| `CROSS_REVIEW_TIMEOUT=480` | Sets how many seconds the reviewer, or an experiment's auditor, may run. The gate waits up to 45 seconds longer before it skips the review. Keep it below about 555: the agent stops the Stop hook after 600 seconds, before the gate can skip the review with a notice. |
| `CROSS_REVIEW_MAX_CHARS=150000` | Sets how much transcript is sent to the reviewer. |
| `CROSS_REVIEW_CLAUDE_BIN`, `CROSS_REVIEW_CODEX_BIN` | Override the reviewer CLI paths, also for `doctor` and experiment audits. |
| `XDG_CACHE_HOME` | Moves the state directory, `~/.cache/verify-gate` by default, to `$XDG_CACHE_HOME/verify-gate`. |

## Per-Project Settings

Settings for one repository go in `~/.config/power-agents/projects.json`, keyed
by the repository's path. A key may start with `~`, and a session in a
subdirectory uses its repository's entry. Outside a repository, the key must
match the session's directory itself:

```json
{
  "~/power-agents": {"check": "./scripts/check.sh"},
  "~/work/client-app": {"cross_review": false}
}
```

| Key | Effect |
| --- | --- |
| `check` | A shell command the gate runs in the repository on turns that changed files, before it sends the self-check. The prompt says whether it passed, failed, or timed out, and includes the last 4,000 characters of output unless it passed. It is stopped after 300 seconds. |
| `cross_review` | `true` or `false`, in place of the global toggle. |
| `cross_review_scope` | `"changes"` or `"all"`, like `CROSS_REVIEW_SCOPE`. |
| `min_chars` | Like `VERIFY_GATE_MIN_CHARS`. |

Environment variables take precedence over this file, and the file over the
global toggle. The file belongs to you, not to the repository, so a repository
you clone cannot choose a command for the gate to run or turn cross-review on.
If the file is invalid (malformed JSON, a top level or entry that is not an
object, an unknown key, a wrong type, a `cross_review_scope` other than
`changes` or `all`, or a relative path), the gate runs no check and keeps
cross-review off unless `CROSS_REVIEW=1` is set. It logs the error as a
`projects` record, and `doctor` reports it.

The check runs through the shell at the top of the repository, not in the
session's subdirectory, with no input and with its error output merged into its
output. A command that cannot start is reported as `could not start`. The agent
waits while the check runs, and the check runs once per turn: edits the agent
makes during its self-check are not checked again. While an
[experiment](experiment.md) runs, it runs once more after the turn, in the
background. When the command exits, the gate stops any processes it left
running.

The full self-check and review prompts are at the top of
[`hooks/verify-gate.py`](../hooks/verify-gate.py). The self-check is a prompt:
the gate cannot confirm that the agent ran the checks it was asked to run.

## The Summary Line

A checked turn ends with one line, joined with ` · ` after `verify gate`:

| Part | When it appears |
| --- | --- |
| `check passed (12s)`, `check failed with exit code 1 (14s)`, `check timed out after 300s (300s)` | The project has a check command and the turn changed files. |
| `self-check fixed`, `self-check found no issues`, `self-check gave no verdict` | Always. It reflects the first line of the agent's reply: `Verification: fixed …`, `Verification: no issues`, or anything else. `, edited files` is added when the self-check changed files. |
| `cross-review (Codex): no material issues` | The reviewer found nothing material. |
| `cross-review (Codex): accepted 2, rejected 1` | The agent's reply to the feedback starts with `Review: accepted N, rejected M`; otherwise `reply gave no counts`. `, edited files` is added when that reply changed files. |
| `cross-review skipped: <reason>` | The reviewer was missing, failed, timed out, or was cancelled. |
| `1 open item`, `3 open items` | The last pass ended with open items. |

Open items are counted from the last line in the reply that is an `Open
items:` heading (also `**Open items:**` or `## Open items`): every non-blank
line after it counts, and so does text on the heading line itself unless it is
"none".

Three kinds of turns end without the line: turns in an experiment's `none` arm,
turns that already used both extra passes, and turns where the gate could not
save its state.

If the files changed during the self-check, the feedback tells the agent that
the review does not cover those edits. A review whose first line is not a
`VERDICT:` line is treated as one that found issues.

Prompts the gate itself sends back to the agent (they start with `Stop hook
feedback:`, `<hook_prompt`, `Automated verification pass`, or `Here is feedback
from another coding agent`) do not start a new turn.

## What the Reviewer Receives

The bundle holds the latest user request (up to 4,000 characters), the session
transcript within `CROSS_REVIEW_MAX_CHARS`, the diff of this turn's changes,
and the list of other uncommitted files. Each tool call and tool result in the
transcript is clipped to 1,500 characters. New untracked files are read up to
40,000 bytes each, binary files appear as `(binary)`, and symbolic links appear
only as their target path. The whole diff is clipped to 40,000 characters.
Private keys, common API tokens, bearer tokens, and `password=`/`token=`-style
values are replaced with `[REDACTED]` before anything is sent.

## Decision Log

Each decision is appended to `log.jsonl` in the state directory,
`$XDG_CACHE_HOME/verify-gate`, or `~/.cache/verify-gate` when `XDG_CACHE_HOME`
is unset. No transcript or diff content is logged. Records hold:

- why a turn qualified (`why`, null for a skipped turn) and the repository it
  ran in
- for a qualifying turn: whether cross-review could run (`review_eligible`),
  the model, and hashes of the gate script (`gate`) and of its four main
  prompts (`prompts`)
- the first line of the agent's verification reply (for example
  `Verification: no issues`), whether it changed file contents or permissions
  during its verification, and how many tool calls it made after the
  verification prompt (read from the last 4 MB of the transcript; empty when
  the prompt isn't found there)
- the tokens the verification used, with cache reads and writes counted
  separately; the reply to a review logs the tokens used since the
  verification prompt
- the project check's result and run time
- the reviewer's verdict or error, its run time, and how long the agent waited
  for it
- the first line of the agent's reply to the feedback (for example
  `Review: accepted 1, rejected 2`), and how many open items each reply listed
- whether the next prompt reads like a correction, and whether the next turn
  changed the same files again
- errors in the settings files, as `projects` or `experiment` records

Since log version 2 (`"v": 2`), records of one turn share a `turn` id.

To summarize the log, run
`python3 ~/.agents/hooks/verify-gate.py stats [--since DAYS]`. It shows:

- raw counts of turns, verification replies, review verdicts, and
  project-check results
- the share of verifications that fixed something; a reply counts as a fix
  when it starts with `Verification:` and contains "fix", "correct", or
  "changed", which is a rough heuristic
- the share of review points the agent accepted, the mean review run time, and
  the mean wait for it
- fix and review rates by trigger (`changed` or `long`) and by repository;
  records from before repositories were logged appear as `unknown`
- the mean verification tokens and the share of verification input read from
  or written to the cache
- the mean verification time, measured from the turn's first `Stop`, so it
  includes the project check and the wait for a review
- how often a review raised points the agent accepted after its self-check
  had found no issues
- how many turns ended with open items, and how often those, and the turns
  without, were followed by a correction
- while an [experiment](experiment.md) runs, its outcomes per arm

Per-session state files and review results in the same directory are deleted
after seven days, when a new prompt arrives. The log itself is never deleted.

## Experiment

To measure whether the gate helps, `~/.config/power-agents/experiment.json`
assigns each qualifying turn at random to no checks, self-check only, or the
full gate. For turns that changed files, the project's check command and,
for a sampled share where cross-review is allowed, a blinded audit then measure
the result in the background. See [Measuring the verify
gate](experiment.md).

## How the Reviewer Is Restricted

Both reviewers are told not to change anything, and both run with hooks
disabled, so a review cannot trigger another review. The technical limits
differ:

- **Claude Code as reviewer** may only use its `Read`, `Grep`, and `Glob` tools,
  and loads no MCP servers.
- **Codex as reviewer** runs with `--sandbox read-only`, which limits its shell
  commands. The gate also disables every MCP server that `codex mcp list` reports
  and turns off the `apps`, `plugins`, `browser_use`, and `computer_use`
  features, whose tools act outside that sandbox. If the server list cannot be
  read, or a server name cannot be safely disabled, the review is skipped with a
  notice. Tools that Codex adds later under other feature names are not covered
  until they are added to `CODEX_EXTERNAL_FEATURES` in the script.

## Cost, Privacy, and Trust

**Cost.** Each qualifying turn costs an extra model pass. With cross-review on,
each qualifying turn that changed files (every qualifying turn with
`CROSS_REVIEW_SCOPE=all`) also costs a full review by the other agent, which
receives up to about 150,000 characters of transcript plus the diff.

**Privacy.** Cross-review sends your session transcript and diff to the *other
vendor*: Claude Code sessions go to Codex (OpenAI), and Codex sessions go to
Claude Code (Anthropic). Secret redaction is best-effort pattern matching only.
Leave cross-review off for work that must not leave its original vendor.
Experiment audits send the diff only where cross-review is allowed. The manual
`review` command sends the diff whatever the setting.

**Codex trust.** Codex skips new or changed hooks until you trust them. After
installing, start a new Codex session and approve the verify-gate hooks with
`/hooks`.

## Changing or Removing the Hooks

Edit gate behavior in [`hooks/verify-gate.py`](../hooks/verify-gate.py) and the
hook entries in [`settings/claude/hooks.json`](../settings/claude/hooks.json)
and [`settings/codex/hooks.json`](../settings/codex/hooks.json), then rerun
`make install`. To remove the hooks, run `make uninstall`; see
[Uninstall](installation.md#uninstall).
