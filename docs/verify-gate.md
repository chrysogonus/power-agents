# Verify Gate and Cross-Review

The verify gate is this repository's core: `make install` always installs it,
with or without the [optional components](installation.md#choosing-components).
Both agents run [`hooks/verify-gate.py`](../hooks/verify-gate.py) on
`UserPromptSubmit` and `Stop`. A turn qualifies when it changed files, or when
the final answer is at least 600 characters and does not end in a question.
Changes include edits to untracked files and commits made during the turn.

- **Self-verification** (on by default): the first `Stop` of a qualifying turn
  sends the agent back once to check its answer against files, tests, or docs.
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
| `CROSS_REVIEW=1` or `CROSS_REVIEW=0` | Forces cross-review on or off for sessions started with it. |
| `CROSS_REVIEW_SCOPE=changes` | Set to `all` to also cross-review long answers from turns that changed no files. |
| `VERIFY_GATE=0` | Disables the gate, including cross-review, for sessions started with it. |
| `VERIFY_GATE_MIN_CHARS=600` | Sets the answer length that makes a turn qualify. |
| `CROSS_REVIEW_TIMEOUT=480` | Sets how many seconds the reviewer may run before it is skipped. |
| `CROSS_REVIEW_MAX_CHARS=150000` | Sets how much transcript is sent to the reviewer. |
| `CROSS_REVIEW_CLAUDE_BIN`, `CROSS_REVIEW_CODEX_BIN` | Override the reviewer CLI paths. |

The full self-check and review prompts are at the top of
[`hooks/verify-gate.py`](../hooks/verify-gate.py). The self-check is a prompt:
the gate cannot confirm that the agent ran the checks it was asked to run.

## Decision Log

Each decision is appended to `~/.cache/verify-gate/log.jsonl`. A record holds
why a turn qualified or was skipped, the first line of the agent's
verification reply (for example `Verification: no issues`), the reviewer's
verdict or error, the reviewer's run time, how long the agent waited for it,
and the first line of the agent's reply to the feedback (for example
`Review: accepted 1, rejected 2`). No transcript or diff content is logged. To
summarize the log, including the share of self-checks that fixed something and
the share of review points the agent accepted, run
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
`make install`. To remove the hooks, follow
[Manual Uninstall](installation.md#manual-uninstall).
