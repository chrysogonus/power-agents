# Skills

Skills are reusable instructions that tell an agent how to handle a particular
kind of task. This repository contains **26 skills**: four core skills and twenty-two
imported skills. Each lives in its own folder with a `SKILL.md` entrypoint.

## Install and Use

Skills are an optional component. Follow the repository's
[quick installation guide](../README.md#installation), then select them:

```bash
./install.sh --components skills   # add other components to the list as needed
```

This links every skill for both Codex and Claude Code. Later runs of
`make install` keep the saved selection.

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
| [`readme-sync`](readme-sync/SKILL.md) | Creates or updates the root `README.md` from the current codebase, keeping accurate sections and checking commands against project files. |

`security-best-practices` is adapted from a pinned
[openai/skills](../THIRD_PARTY_NOTICES.md) path, so `make skills-outdated`
checks it together with the imported skills.

## Imported Skills

These twenty-two skills are included in the same installation and use normal automatic
discovery. They are experimental: live routing and task-effect evaluations remain
unmeasured. Each package includes its required references, license, and
routing fixtures (see [Skill Format](#skill-format)). Pinned origins and
adaptations are recorded in
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
| [`test-driven-development`](test-driven-development/SKILL.md) | Failing test first for new behavior and bug fixes, alongside ponytail, where the project can run tests. |
| [`systematic-debugging`](systematic-debugging/SKILL.md) | Root-cause investigation of bugs, test failures, and unexpected behavior before any fix. |
| [`frontend-design`](frontend-design/SKILL.md) | New frontend UI and intentional visual design from a product brief, including app screens, dashboards, and components. |
| [`design-taste-frontend`](design-taste-frontend/SKILL.md) | Art direction and a real-browser check loop for public-facing web pages, or pages that look generic. Its scripts need Node 22+ and Chromium. |
| [`agent-browser`](agent-browser/SKILL.md) | Real-browser interaction such as clicking, forms, logins, screenshots, and UI-flow testing. Needs the separately installed `agent-browser` CLI. |
| [`improve-codebase-architecture`](improve-codebase-architecture/SKILL.md) | Codebase-wide scan for deepening opportunities, reported as HTML outside the repository, then a grilling loop on the chosen candidate. |
| [`codebase-design`](codebase-design/SKILL.md) | Deep-module vocabulary for designing one module's interface and seams. |
| [`domain-modeling`](domain-modeling/SKILL.md) | Sharpening domain terms in `GLOSSARY.md` and recording ADRs. |
| [`triage`](triage/SKILL.md) | Issue-tracker triage states, verification, and agent briefs, with confirmation before tracker writes. |
| [`handoff`](handoff/SKILL.md) | A handoff document, outside the workspace, for continuing the session in a fresh agent. |
| [`using-git-worktrees`](using-git-worktrees/SKILL.md) | A requested isolated workspace: detects existing isolation, prefers the runtime's native worktree tool, and falls back to `git worktree`. |
| [`finishing-a-development-branch`](finishing-a-development-branch/SKILL.md) | Wrapping up a finished branch or worktree: checks first, then a local merge, a pull request, or keeping it, as the user chooses. |
| [`claude-skill-creator`](claude-skill-creator/SKILL.md) | Drafting and testing skills with Claude Code runs, benchmarks, a review viewer, and description-trigger optimization. Runs make paid model calls through the `claude` CLI. |

`grilling` applies when an interview is requested; routine implementation does
not require that interview.
Ponytail applies to its current task and does not install session hooks.

## Choosing Between Related Skills

General code reviews use the built-in review / `review-report` boundary below.
Design work belongs to `frontend-design`, except public-facing web pages, which
belong to `design-taste-frontend`; content stress-testing to `break-ui`; driving a
real browser to `agent-browser`;
React performance to `vercel-react-best-practices`; component API design to
`vercel-composition-patterns`. New behavior and bug fixes use `ponytail`
together with `test-driven-development` when tests can run; finding a bug's
root cause belongs to `systematic-debugging`, and measured slowdowns to
`performance-optimization`. A codebase-wide architecture scan belongs to
`improve-codebase-architecture`, one module's interface design to
`codebase-design`, and readability refactors to `code-simplification`; domain
terms and ADRs belong to `domain-modeling`, issue-tracker work to `triage`, and
session handoffs to `handoff`. Creating an isolated worktree belongs to
`using-git-worktrees` and integrating a finished branch to
`finishing-a-development-branch`. Editing agent instruction files belongs to
`writing-for-agents`, while testing a skill through Claude Code runs,
benchmarks, or description-trigger optimization belongs to
`claude-skill-creator`; it is renamed from upstream `skill-creator` so it does
not shadow the skill-creator bundled with Codex, which remains the choice for
Codex skills. Existing plugin or unmanaged skills remain
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

The validator (`scripts/validate-skills.py`, run by `./install.sh` and
`make check`) treats every directory under `skills/` as a skill and also
requires a non-empty Markdown body after the frontmatter.

Supporting scripts, references, or assets belong inside the same skill
directory. Behavioral evaluation cases use the Agent Skills
`evals/evals.json` format with realistic prompts, expected outputs, and
objective assertions where possible. The `evals/` directory is optional; when it
exists, the validator requires:

- `evals/evals.json` with `skill_name` equal to the directory name and a
  non-empty `evals` array;
- per case, a unique integer `id` and non-empty `prompt` and `expected_output`
  strings;
- optionally, `assertions` as a non-empty array of non-empty strings (without
  it, `expected_output` is the only graded assertion), a `routing` object as
  described below, and `files` naming existing files inside the skill
  directory.

Run `make eval` to execute the fixtures using paid Anthropic API calls or a Claude
subscription token, or use `make eval EVAL_ARGS='--skill review-report'` to
select one fixture set while keeping all skills available for routing. See the repository's
[evaluation instructions](../docs/development.md#behavioral-skill-evaluations) for runtime,
credentials, repetition, grading, and result details. `make check` validates
fixtures and tests the runner offline; it does not execute LLM evaluations.
All 26 skills now have fixture sets, including security-specific positive and
negative cases and simple questions that should load no skill. Every case has
a `routing` object. This is coverage, not evidence of live routing success.

Fixtures can add a `routing` object:

```json
{"required": ["review-report"], "forbidden": ["ponytail"]}
```

`required` lists skills that must successfully load; `allowed`, when present,
limits all loads; `forbidden` lists skills that must not load. Lists contain
unique existing skill names. Required skills must be allowed and cannot be
forbidden; an empty object `{}` is invalid. Use `{"allowed": []}` for a no-skill
task. When `routing` is absent,
the old requirement to load any repository skill remains for compatibility.
The judge still grades response assertions; routing checks do not depend on its
opinion. Reports include missing required skills and unexpected activations.
Keep prompts natural, and test explicit invocation separately. The
`review-report` and `security-best-practices` review fixtures use distinct
prompts. Twelve other sets still share one identical review prompt ("Review this PR
for correctness and security before merge…") as a shared negative case, and many of the
older imported sets' remaining cases are legacy prompts that tell the agent to load a
skill first.

Compare global instruction variants with `--instructions baseline|none`
or `--instruction-file PATH`. See the [comparison protocol](../docs/modernization.md)
for isolation, interpretation, and external instruction conflicts.

## Adding a Skill

Create the directory and `SKILL.md`, then run `./install.sh` from the repository
root, with the `skills` component selected, to validate all skill names and create the new per-skill links for Codex
and Claude Code. Existing unrelated skills in either agent's skill directory
remain untouched. Run `make check` to validate the change. Edits to an
already linked skill are available immediately through its link.
