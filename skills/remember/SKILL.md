---
name: remember
description: Use when the user asks to remember, update, or forget something for all projects and both agents, such as a fact about themselves, their machines and tools, or a recurring decision, or confirms such an entry you proposed, including a request to remember a secret, which it declines. Saves to the shared memory store in ~/.agents/memory and never stores secrets or credentials. Not for facts about the current project only, standing rules for how agents should work (those go in the instructions overlay), or session handoffs (use handoff).
metadata:
  evaluation-status: unmeasured
---

# Remember

The shared memory store is `~/.agents/memory/`: one fact per Markdown file,
listed in `MEMORY.md`. Claude Code and Codex both read it, and the `context`
component shows the index at session start. The store is a local git
repository. Never add a remote to it or push it.

## What belongs where

| The information | Where it goes |
| --- | --- |
| Holds across projects: who the user is, their machines and tools, recurring decisions, external references | This store |
| Only about the current project | The project's `AGENTS.md`, or Claude Code's per-project memory. Not this skill |
| An instruction for how agents should work from now on ("from now on, always…"), given without asking you to remember it | Offer to add it to `~/.config/power-agents/instructions.md`, the user's instructions overlay, and to rerun the Power Agents installer. Do not save it here |
| Secrets, credentials, or other people's personal data | Nowhere. Decline even if the user asks again, and suggest a credential helper, a password manager, or an environment variable |

When the user explicitly asks you to remember something that is not a secret,
save it here even if it contains "always" or "never", such as "remember that I
use pnpm, never npm".

## Save

1. Save only what the user asked you to remember. If you noticed a fact
   yourself, propose the entry (name, type, and description) and wait for a
   yes.
2. Check `MEMORY.md` (in your session context, or read it) for an entry on the
   same subject. Update that entry with `--replace` instead of adding a
   near-duplicate. If its name no longer fits, save the fact under a new name
   and forget the old entry, so that one entry remains.
3. Pick a type:
   - `user`: who the user is, their role, preferences, and environment.
   - `feedback`: guidance on how to work with them. Follow the fact with
     **Why:** and **How to apply:** lines.
   - `project`: a cross-project initiative or constraint. Write dates as
     absolute dates.
   - `reference`: a pointer to an external resource, such as a URL or a
     dashboard.
4. Run the script in this skill's directory, with the fact as the body on
   standard input:

   ```bash
   python3 <skill-directory>/scripts/memory.py save NAME --type TYPE \
     --description "One line that tells a future agent when this matters" <<'EOF'
   The fact, in a few sentences.
   EOF
   ```

   `NAME` is a short lowercase slug such as `prefers-pnpm`. The script records
   the source project, session, and date, rebuilds `MEMORY.md`, and commits.
   It refuses an existing name unless you pass `--replace`. Codex asks for
   approval because the store is outside the workspace; that is expected.
5. Tell the user the path of the saved file.

## Forget or correct

Run `memory.py forget NAME` when the user asks you to forget something. When a
memory turns out to be wrong or outdated, update or forget it instead of
working around it. After editing memory files by hand, run `memory.py index`.

## Recall

Read a memory file when its index line bears on the task. A memory describes
what was true when it was written: check that a file, command, or flag it names
still exists before you rely on it.
