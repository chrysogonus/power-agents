# Skills

Skills are reusable instructions that tell an agent how to handle a particular
kind of task. This repository contains **13 skills**: three core skills and ten
imported skills. Each lives in its own folder with a `SKILL.md` entrypoint.

## Install and Use

Follow the repository's [quick installation guide](../README.md#installation).
`make install` links every skill for both Codex and Claude Code; there is no
separate skill-installation step.

Ask for a skill explicitly, or let the agent select one from your request:

| Agent | Example prompt |
| --- | --- |
| Codex | `$review-report write a plain-language review of this branch` |
| Claude Code | `/review-report write a plain-language review of this branch` |

For a minimal implementation or bug fix, use `ponytail`. For a general code
review, use the runtime's built-in review (`/review` in Codex, `/code-review` in
Claude Code). For a plain-language `CODE_REVIEW.md` with verified findings and
paste-ready PR comments, use `review-report`.

## Available Skills

### Core Skills

| Skill | Purpose |
| --- | --- |
| [`review-report`](review-report/SKILL.md) | Writes `CODE_REVIEW.md` with verified, plain-language findings, concrete examples, and paste-ready review comments, starting from the runtime's built-in review. |
| [`prompt-refiner`](prompt-refiner/SKILL.md) | Improves existing prompts and drafts new non-coding prompts. |
| [`security-best-practices`](security-best-practices/SKILL.md) | Provides explicitly requested security reviews and guidance for Python, JavaScript/TypeScript, and Go. |

## Imported Skills

These ten skills are included in the same installation and use normal automatic
discovery. They are experimental: live routing and task-effect evaluations remain
unmeasured. Each package includes its required references, license, and routing
fixtures. Pinned origins and adaptations are recorded in
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

`grilling` applies when an interview is requested; routine implementation does
not require that interview.
Ponytail applies to its current task and does not install session hooks.

## Choosing Between Related Skills

General code reviews use the built-in review / `review-report` boundary below.
Design work belongs to `frontend-design`; content stress-testing to `break-ui`;
React performance to `vercel-react-best-practices`; component API design to
`vercel-composition-patterns`. Existing plugin or unmanaged skills remain
outside this repository's routing inventory.

`review-report` uses a distinct name so it does not shadow the bundled review
commands (`/review` in Codex, `/code-review` in Claude Code).

`review-report` handles findings requested in a file, plain-language reviews for
readers without codebase context, and paste-ready review comments. Every other
code review request goes to the runtime's built-in review. `review-report`
starts from that review where the agent can run it (Claude Code's `code-review`
skill, or `/review` findings the user already produced in Codex) and verifies
every finding before writing it down. Its evaluation cases cover both sides of
this boundary.

`prompt-refiner` handles an existing prompt draft or a new non-coding prompt;
raw coding-task notes intended for a coding-agent handoff are outside its
scope, and its evaluation cases cover that boundary.

## Skill Format

Each skill directory must contain a `SKILL.md` with YAML frontmatter containing
`name` and `description`. The `name` must exactly match the directory name and
use lowercase letters and digits, optionally separated by single hyphens. The
description should state what the skill does and when an agent should load it.

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

Run `make eval` to execute the fixtures using paid Anthropic API calls, or use
`make eval EVAL_ARGS='--skill review-report'` to select one fixture set while
keeping all skills available for routing. See the repository's
[evaluation instructions](../docs/development.md#behavioral-skill-evaluations) for runtime,
credentials, repetition, grading, and result details. `make check` validates
fixtures and tests the runner offline; it does not execute LLM evaluations.
All 13 skills now have fixture sets, including security-specific positive and
negative cases and simple questions that should load no skill. This is coverage,
not evidence of live routing success.

Fixtures can add a `routing` object:

```json
{"required": ["review-report"], "forbidden": ["ponytail"]}
```

`required` lists skills that must successfully load; `allowed`, when present,
limits all loads; `forbidden` lists skills that must not load. Lists contain
unique existing skill names. Required skills must be allowed and cannot be
forbidden. Use `{"allowed": []}` for a no-skill task. When `routing` is absent,
the old requirement to load any repository skill remains for compatibility.
The judge still grades response assertions; routing checks do not depend on its
opinion. Reports include missing required skills and unexpected activations.
Keep prompts natural, and test explicit invocation separately. Review routing
fixtures use distinct prompts; other legacy fixture sets are retained.

Compare global instruction variants with `--instructions baseline|candidate|none`
or `--instruction-file PATH`. See the [comparison protocol](../docs/modernization.md)
for isolation, interpretation, and external instruction conflicts.

## Adding a Skill

Create the directory and `SKILL.md`, then run `./install.sh` from the repository
root to validate all skill names and create the new per-skill links for Codex
and Claude Code. Existing unrelated skills in either agent's skill directory
remain untouched. Run `make check` to validate the change. Edits to an
already linked skill are available immediately through its link.
