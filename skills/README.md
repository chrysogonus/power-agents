# Skills

Reusable, agent-agnostic skills: a folder per skill, each with a `SKILL.md`.

## Available Skills

| Skill | Purpose |
| --- | --- |
| [`deep-review`](deep-review/SKILL.md) | Reviews pull requests and merge requests for security, privacy, reliability, and maintainability. |
| [`coding-agent-brief`](coding-agent-brief/SKILL.md) | Turns rough task descriptions and context into ready-to-use coding-agent briefs. |
| [`review-report`](review-report/SKILL.md) | Reviews the current branch against its base and writes detailed findings to `CODE_REVIEW.md`. |
| [`prompt-refiner`](prompt-refiner/SKILL.md) | Improves existing prompts and drafts new non-coding prompts. |
| [`security-best-practices`](security-best-practices/SKILL.md) | Provides security best-practice reviews and guidance for supported languages and frameworks. |

## Imported Skills

These ten skills are installed with normal automatic discovery, as requested.
They are experimental: live routing and task-effect evaluations remain
unmeasured. Each package includes its required references, license, and four
routing fixtures. Pinned origins and adaptations are recorded in
[Third-Party Notices](../THIRD_PARTY_NOTICES.md#skills-integrated-from-the-research-catalog).

| Skill | Purpose and boundary |
| --- | --- |
| [`ponytail`](ponytail/SKILL.md) | Minimal new implementations and bug fixes using existing, standard-library, or native features. |
| [`writing-for-agents`](writing-for-agents/SKILL.md) | Agent-facing instruction files, descriptions, context pointers, and completion criteria. |
| [`grilling`](grilling/SKILL.md) | Critical interviews when the user asks to stress-test an idea or decision. |
| [`vercel-react-best-practices`](vercel-react-best-practices/SKILL.md) | React/Next.js implementation and measured performance problems. |
| [`vercel-composition-patterns`](vercel-composition-patterns/SKILL.md) | Reusable React APIs, composition, and boolean-prop proliferation. |
| [`supabase-postgres-best-practices`](supabase-postgres-best-practices/SKILL.md) | Postgres SQL, schema, migrations, query plans, and RLS. |
| [`break-ui`](break-ui/SKILL.md) | Realistic worst-case UI data and edge cases, preserving visual identity. |
| [`code-simplification`](code-simplification/SKILL.md) | Readability refactors of working code with unchanged behavior. |
| [`performance-optimization`](performance-optimization/SKILL.md) | Measured application bottlenecks beyond React/Next.js and Postgres-specific work. |
| [`frontend-design`](frontend-design/SKILL.md) | New frontend UI and intentional visual design from a product brief. |

Invoke any skill explicitly as `$skill-name` in Codex or `/skill-name` in Claude
Code, or let the agent select it from the request. `grilling` applies when an
interview is requested; routine implementation does not require that interview.
Ponytail applies to its current task and does not install session hooks.

General code reviews retain the `deep-review` / `review-report` boundary below.
Design work belongs to `frontend-design`; content stress-testing to `break-ui`;
React performance to `vercel-react-best-practices`; component API design to
`vercel-composition-patterns`. Existing plugin or unmanaged skills remain
outside this repository's routing inventory.

The review skills use distinct names so personal installation does not shadow
bundled or project review skills. Neither `deep-review` nor `review-report`
collides with a bundled skill or command alias in the checked installations:
Claude Code 2.1.226 and Codex CLI 0.152.1 (checked on 2026-10-05 against CLI help,
installed binaries, and Codex's bundled skill entrypoints).

`review-report` handles findings requested in a file, plain-language reviews for
readers without codebase context, and paste-ready review comments. `deep-review`
handles every other code review request. `review-report` may invoke
`deep-review` for its analysis after routing. Both skills include evaluation
cases on both sides of this boundary.

`coding-agent-brief` handles raw coding-task notes intended for handoff to a
coding agent. `prompt-refiner` handles an existing prompt draft or a new
non-coding prompt. Their evaluation cases include both sides of this routing
boundary.

## Skill Format

Each skill directory must contain a `SKILL.md` with YAML frontmatter containing
`name` and `description`. The `name` must exactly match the directory name and
use lowercase letters, digits, and hyphens. The description should state what
the skill does and when an agent should load it.

Minimum example:

```markdown
---
name: skill-name
description: Explain what this does and when an agent should use it.
---

# Skill Name

Follow the workflow described here.
```

Supporting scripts, references, or assets belong inside the same skill
directory. Behavioral evaluation cases use the Agent Skills
`evals/evals.json` format with realistic prompts, expected outputs, and
objective assertions where possible.

Run `make eval` to execute the fixtures, or use
`make eval EVAL_ARGS='--skill deep-review'` to select one fixture set while
keeping all skills available for routing. See the repository's
[evaluation instructions](../README.md#behavioral-skill-evaluations) for runtime,
credentials, repetition, grading, and result details. `make check` validates
fixtures and tests the runner offline; it does not execute LLM evaluations.

## Adding a Skill

Create the directory and `SKILL.md`, then run `./install.sh` from the repository
root to validate all skill names and create the new per-skill links for Codex
and Claude Code. Existing unrelated skills in either agent's skill directory
remain untouched.
