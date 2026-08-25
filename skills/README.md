# Skills

Reusable, agent-agnostic skills: a folder per skill, each with a `SKILL.md`.

## Available Skills

| Skill | Purpose |
| --- | --- |
| [`code-review`](code-review/SKILL.md) | Reviews pull requests and merge requests for security, privacy, reliability, and maintainability. |
| [`coding-agent-brief`](coding-agent-brief/SKILL.md) | Turns rough task descriptions and context into ready-to-use coding-agent briefs. |
| [`github-code-review`](github-code-review/SKILL.md) | Reviews the current branch against its base and writes detailed findings to `CODE_REVIEW.md`. |
| [`prompt-refiner`](prompt-refiner/SKILL.md) | Rewrites rough or poorly structured prompts into clear, copy-pasteable prompts. |
| [`security-best-practices`](security-best-practices/SKILL.md) | Provides security best-practice reviews and guidance for supported languages and frameworks. |

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
directory.

## Adding a Skill

Create the directory and `SKILL.md`, then run `./install.sh` from the repository
root to validate all skill names and create the new per-skill links for Codex
and Claude Code. Existing unrelated skills in either agent's skill directory
remain untouched.
