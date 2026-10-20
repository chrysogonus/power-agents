# Verify Gate and Cross-Review

Both agents run [`hooks/verify-gate.py`](../hooks/verify-gate.py) on
`UserPromptSubmit` and `Stop`. A turn qualifies when it changed files in the
working tree, or when the final answer is at least 600 characters and does not
end in a question.

- **Self-verification** (on by default): the first `Stop` of a qualifying turn
  sends the agent back once to check its answer against files, tests, or docs.
- **Cross-review** (off by default): after verification, the session transcript
  and `git diff` go to the *other* agent, which runs read-only. Its feedback is
  returned as "Here is feedback from another coding agent. What do you think
  about this?" A missing, failing, or timed-out reviewer is skipped with a
  notice; it never blocks the turn.

## Controls

| Control | Effect |
| --- | --- |
| `python3 ~/.agents/hooks/verify-gate.py cross-review on\|off\|status` | Persistently toggles cross-review through `~/.config/power-agents/cross-review-on`. |
| `CROSS_REVIEW=1` or `CROSS_REVIEW=0` | Forces cross-review on or off for sessions started with it. |
| `VERIFY_GATE=0` | Disables the gate, including cross-review, for sessions started with it. |

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
