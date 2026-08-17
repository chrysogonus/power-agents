# Global Coding Instructions

Adapted from the
[Karpathy-Inspired Claude Code Guidelines](https://github.com/multica-ai/andrej-karpathy-skills/blob/main/CLAUDE.md)
(MIT). These guidelines reduce common coding-agent mistakes and should be
combined with repository-specific instructions.

Tradeoff: They bias toward caution over speed. Use judgment for trivial tasks.

## Repository Context

- Follow repository-specific instructions when they conflict with these global instructions.
- Read relevant repository instructions and follow existing conventions before making changes.

## 1. Think Before Coding

Do not assume or hide confusion. Surface assumptions and tradeoffs.

Before implementing:

- State assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them instead of choosing silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop, identify what is confusing, and ask.

## 2. Simplicity First

Write the minimum code that solves the problem. Add nothing speculative.

- Do not add features beyond what was requested.
- Do not create abstractions for single-use code.
- Do not add flexibility or configurability that was not requested.
- Do not add error handling for impossible scenarios.
- If 200 lines could reasonably be 50, simplify the implementation.

Ask whether a senior engineer would consider the solution overcomplicated. If
so, simplify it.

## 3. Surgical Changes

Touch only what is necessary. Clean up only what your changes make obsolete.

When editing existing code:

- Do not improve adjacent code, comments, or formatting unrelated to the task.
- Do not refactor code that is not part of the requested change.
- Match the existing style even when you would choose a different approach.
- Mention unrelated dead code rather than deleting it.
- Preserve unrelated user changes and do not revert work outside the task.

When your changes create unused code:

- Remove imports, variables, and functions made unused by your changes.
- Do not remove pre-existing dead code unless asked.

Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

Define success criteria and continue until the result is verified.

Transform tasks into verifiable goals:

- "Add validation" becomes "write tests for invalid inputs, then make them pass."
- "Fix the bug" becomes "write a test that reproduces it, then make it pass."
- "Refactor X" becomes "ensure relevant tests pass before and after."

For multi-step tasks, state a brief plan in which every step has a verification
check. Strong success criteria support independent execution; vague criteria
require clarification.

## Scope and Safety

- For requests to explain, review, diagnose, or plan, inspect and report without changing files unless asked.
- For requested implementation work, make focused in-scope changes and run relevant checks.
- Do not perform destructive actions, external writes, or material scope expansion unless explicitly requested.
- Never expose secrets, credentials, or other sensitive data.

## Verification

- Run relevant tests after changing behavior.
- Run available linting and formatting checks when appropriate.
- Never claim a command, test, or check passed unless it was actually executed.

## Git

- Do not commit unless explicitly requested.
- Do not push unless explicitly requested.
- Do not rewrite existing commits unless explicitly requested.

These guidelines are working when diffs contain fewer unnecessary changes,
solutions avoid needless complexity, and clarification happens before mistaken
implementation rather than afterward.
