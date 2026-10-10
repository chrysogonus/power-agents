# Global Coding Instructions

Adapted from the
[Karpathy-Inspired Claude Code Guidelines](https://github.com/multica-ai/andrej-karpathy-skills/blob/main/CLAUDE.md)
(MIT). These guidelines reduce common coding-agent mistakes and should be
combined with repository-specific instructions.

Tradeoff: They bias toward caution over speed. Use judgment for trivial tasks.

## Repository Context

- Follow repository-specific instructions when they conflict with these global instructions.
- Read relevant repository instructions and follow existing conventions before making changes.

## Skill Selection

Use the smallest set of skills that covers the current task or phase.
User instructions and project conventions take precedence over these defaults.
Honor explicitly requested skills within their stated scope.

### Primary skills

- Visual design and redesign: use frontend-design as the primary design
  skill. Use alternative aesthetic skills when explicitly requested.
- Refactoring working code: use code-simplification. Preserve behavior
  unless a behavior change is explicitly requested.
- New functionality and bug fixes: use ponytail at full intensity,
  unless the user requests another level.
- UI content stress-testing: use break-ui.
- General code review: use deep-review. Use review-report for findings
  requested in a file, explanations for readers without codebase context,
  or paste-ready review comments.

### Supporting skills

Load a supporting skill when it addresses a distinct concern:

- React component APIs and composition: vercel-composition-patterns.
- React/Next.js implementation and performance:
  vercel-react-best-practices.
- Postgres queries, schemas, migrations, and RLS:
  supabase-postgres-best-practices.
- Measured performance bottlenecks outside those areas:
  performance-optimization.
- Explicit security guidance or reviews: security-best-practices.

For other tasks, select skills using their documented descriptions.
Keep one primary owner for each concern. Additional skills should provide
complementary guidance rather than competing workflows.

For work combining redesign and refactoring, distinguish intended UX
changes from behavior-preserving cleanup and verify both.

## 1. Think Before Coding

Do not assume or hide confusion. Surface assumptions and tradeoffs.

Before implementing:

- Resolve uncertainty from repository instructions, existing code, and available
  tools first.
- Ask when remaining ambiguity materially affects correctness, scope, or safety.
  Otherwise, follow existing conventions and state material assumptions.
- If a simpler approach exists, say so. Push back when warranted.

## 2. Simplicity First

Write the minimum code that solves the problem. Add nothing speculative.

- Do not add features beyond what was requested.
- Introduce abstractions only when they make the current implementation clearer
  or remove meaningful duplication.
- Do not add flexibility or configurability that was not requested.
- Avoid defensive code for scenarios excluded by established contracts or
  invariants.
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
- When an automated regression test cannot reasonably cover the change, explain
  the limitation and perform the most relevant available verification.
- Run available linting and formatting checks when appropriate.
- Never claim a command, test, or check passed unless it was actually executed.
- Report checks performed and their results. If verification is blocked, explain
  why and what remains unverified.
- Identify failures as pre-existing only when supported by evidence.

## Git

- Do not commit unless explicitly requested.
- Do not push unless explicitly requested.
- Do not rewrite existing commits unless explicitly requested.

These guidelines are working when diffs contain fewer unnecessary changes,
solutions avoid needless complexity, and clarification happens before mistaken
implementation rather than afterward.
