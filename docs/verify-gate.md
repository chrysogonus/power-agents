# Verify Gate and Cross-Review

The verify gate is this repository's core: `make install` always installs it,
with or without the [optional components](installation.md#choosing-components).
Both agents run [`hooks/verify-gate.py`](../hooks/verify-gate.py) on
`UserPromptSubmit` and `Stop`. A turn qualifies when it changed files, or when
the final answer is at least 600 characters and does not end in a question.
Changes include edits to untracked files and commits made during the turn.

- **Self-verification** (on by default): the first `Stop` of a qualifying turn
  sends the agent back once to check its answer against files, tests, or docs.
  If the repository has a [check command](#per-project-settings), the gate runs
  it first and adds the result to that prompt.
- **Cross-review** (off by default): at that same `Stop`, the *other* agent
  starts in the background, runs read-only, and reviews while the agent
  verifies. It receives the latest user request, the session transcript, and
  the diff of this turn's changes, including commits and the contents of new
  untracked files. Files that were already modified before the turn are listed
  separately, not diffed. By default only turns that changed files are
  reviewed. At the next `Stop`, the gate waits for the review. If the reviewer
  reports no material issues, the turn ends with a notice. Otherwise the
  feedback is returned as "Here is feedback from another coding agent. What do
  you think about this?" A missing, failing, or timed-out reviewer is skipped
  with a notice; it never blocks the turn. A new prompt stops a review that is
  still running.

## Controls

| Control | Effect |
| --- | --- |
| `python3 ~/.agents/hooks/verify-gate.py cross-review on\|off\|status` | Persistently toggles cross-review through `~/.config/power-agents/cross-review-on`. |
| `python3 ~/.agents/hooks/verify-gate.py doctor` | Checks that both agents' hook entries run the gate, the state directory is writable, and, when cross-review is on, that both reviewer CLIs are on PATH and the Codex reviewer's MCP servers can be disabled. Exits 1 if a required check fails. |
| `python3 ~/.agents/hooks/verify-gate.py review --agent claude\|codex [--base REF] [--focus TEXT]` | Runs a review now, outside the gate, and prints it. With `--agent` the *other* agent reviews; name the reviewer directly with `--reviewer`. It reviews uncommitted and untracked changes, or with `--base` also the commits since the merge base with `REF`. `--focus` tells the reviewer what to concentrate on. No transcript is sent; the reviewer runs with the same restrictions as in the gate. |
| `python3 ~/.agents/hooks/verify-gate.py status` | Lists background reviews that are still running, per session. |
| `python3 ~/.agents/hooks/verify-gate.py cancel [SESSION]` | Stops running background reviews, or only that session's. The gate then skips the review with a notice. |
| `CROSS_REVIEW=1` or `CROSS_REVIEW=0` | Forces cross-review on or off for sessions started with it. |
| `CROSS_REVIEW_SCOPE=changes` | Set to `all` to also cross-review long answers from turns that changed no files. |
| `VERIFY_GATE=0` | Disables the gate, including cross-review, for sessions started with it. |
| `VERIFY_GATE_MIN_CHARS=600` | Sets the answer length that makes a turn qualify. |
| `CROSS_REVIEW_TIMEOUT=480` | Sets how many seconds the reviewer may run before it is skipped. |
| `CROSS_REVIEW_MAX_CHARS=150000` | Sets how much transcript is sent to the reviewer. |
| `CROSS_REVIEW_CLAUDE_BIN`, `CROSS_REVIEW_CODEX_BIN` | Override the reviewer CLI paths. |

## Per-Project Settings

Settings for one repository go in `~/.config/power-agents/projects.json`, keyed
by the repository's path. A key may start with `~`, and a session in a
subdirectory uses its repository's entry:

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
If the file is invalid (malformed JSON, an unknown key, a wrong type, or a
relative path), the gate runs no check and keeps cross-review off unless
`CROSS_REVIEW=1` is set, and `doctor` reports the error.

The agent waits while the check runs, and the check runs once per turn: edits
the agent makes during its self-check are not checked again. When the command
exits, the gate stops any processes it left running.

The full self-check and review prompts are at the top of
[`hooks/verify-gate.py`](../hooks/verify-gate.py). The self-check is a prompt:
the gate cannot confirm that the agent ran the checks it was asked to run.

## Decision Log

Each decision is appended to `~/.cache/verify-gate/log.jsonl`. A record holds
why a turn qualified or was skipped, the first line of the agent's verification
reply (for example `Verification: no issues`), how many tool calls the agent
made after the verification prompt (read from the last 4 MB of the transcript;
empty when the prompt isn't found there), the project check's result and run
time, the reviewer's verdict or error, the reviewer's run time, how long the
agent waited for it, and the first line of the agent's reply to the feedback
(for example `Review: accepted 1, rejected 2`). No transcript or diff content is
logged. To summarize the log, including the share of self-checks that fixed
something and the share of review points the agent accepted, run
`python3 ~/.agents/hooks/verify-gate.py stats`. Per-session state files in the
same directory are deleted after seven days.

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
it also costs a full review by the other agent, which receives up to about
150,000 characters of transcript plus the diff.

**Privacy.** Cross-review sends your session transcript and diff to the *other
vendor*: Claude Code sessions go to Codex (OpenAI), and Codex sessions go to
Claude Code (Anthropic). Secret redaction is best-effort pattern matching only.
Leave cross-review off for work that must not leave its original vendor.

**Codex trust.** Codex skips new or changed hooks until you trust them. After
installing, start a new Codex session and approve the verify-gate hooks with
`/hooks`.

## Changing or Removing the Hooks

Edit gate behavior in [`hooks/verify-gate.py`](../hooks/verify-gate.py) and the
hook entries in [`settings/claude/hooks.json`](../settings/claude/hooks.json)
and [`settings/codex/hooks.json`](../settings/codex/hooks.json), then rerun
`make install`. To remove the hooks, run `make uninstall`; see
[Uninstall](installation.md#uninstall).
