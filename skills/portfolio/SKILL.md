---
name: portfolio
description: Use only when the user's question spans several of their projects or repositories, such as what they are working on across projects, which of their repositories have uncommitted work, other active agent sessions, or handoffs left by earlier sessions, or which project to work on next. Reads ~/.agents/portfolio.json, kept by the Power Agents context component. Not for a question about the current repository alone, such as its changed files or status (use git), and not for writing a handoff (use handoff).
metadata:
  evaluation-status: unmeasured
---

# Portfolio

The `context` component records each git repository where a Codex or Claude
Code session starts in `~/.agents/portfolio.json`, and keeps session locks and
handoffs under `~/.agents/`.

1. Run:

   ```bash
   python3 ~/.agents/hooks/agent-hub.py portfolio
   ```

   It prints one row per project, most recent first: branch, uncommitted
   changes, other active sessions, waiting handoffs, the last session, and the
   path. If the script is missing, tell the user that the portfolio needs the
   Power Agents `context` component and stop.
2. Answer the user's question from the table. Lead with what needs attention:
   uncommitted changes, waiting handoffs, and projects another session is
   working in. Keep it short; do not repeat the whole table unless asked.
3. Do not change any repository, handoff, or lock. A project marked
   `(missing)` no longer exists at that path; remove its entry from
   `portfolio.json` only if the user asks.
