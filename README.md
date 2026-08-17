# Shared Coding-Agent Configuration

This repository is the canonical home for personal instructions and reusable
skills shared across Codex, Claude Code, and GitHub Copilot.

## Layout

```text
~/.agents/
├── instructions/
│   └── general-global.md
├── skills/
│   └── <skill-name>/
│       └── SKILL.md
├── install.sh
└── sync.sh
```

## Installation

Clone the repository into `~/.agents`, then run the installer:

```bash
git clone git@github-personal:chrysogonus/power-rangents.git ~/.agents
cd ~/.agents
./install.sh
```

The installer is safe to rerun. It creates these instruction links:

| Agent | Installed instruction file |
| --- | --- |
| Codex | `~/.codex/AGENTS.md` |
| Claude Code | `~/.claude/CLAUDE.md` |
| GitHub Copilot CLI | `~/.copilot/copilot-instructions.md` |

Codex and GitHub Copilot discover skills directly from `~/.agents/skills`.
Claude Code expects personal skills in `~/.claude/skills`, so the installer
creates one symlink there for each central skill. Other Claude-only skills are
left untouched.

When an existing file or same-named skill conflicts with an installed link,
the installer moves it to a timestamped directory under `~/.agents-backups`.
It also backs up same-named legacy copies under `~/.codex/skills`, because
leaving those copies in place can register a central skill twice.

GitHub Copilot surfaces do not all share the same local configuration. The
instruction link above applies to Copilot CLI. IDE and GitHub.com instruction
support may also require personal settings or repository-level files such as
`.github/copilot-instructions.md`.

## Syncing

Pull fast-forward updates and reinstall links in one command:

```bash
~/.agents/sync.sh
```

`sync.sh` uses `git pull --ff-only`, so it stops rather than creating a merge
commit when local and remote history have diverged.

## Adding or Updating a Skill

1. Create `skills/<skill-name>/SKILL.md`.
2. Add YAML frontmatter containing `name` and `description`.
3. Make the `name` exactly match the directory name. Use lowercase letters,
   digits, and hyphens.
4. Put supporting scripts, references, or assets inside the skill directory.
5. Run `./install.sh` to expose the skill to Claude Code. Codex and Copilot
   discover the central directory directly.

Example:

```markdown
---
name: example-skill
description: Explain what the skill does and when an agent should use it.
---

# Example Skill

Follow the workflow described here.
```

## New-Machine Setup

1. Install the agents you use and Git.
2. Configure SSH access for the `github-personal` host alias, or clone with an
   HTTPS URL and update the remote as needed.
3. Clone this repository to `~/.agents`.
4. Optionally configure the repository-local Git identity:

   ```bash
   git config --local user.name "Your Name"
   git config --local user.email "your-address@example.com"
   ```

5. Run `./install.sh`.
6. Restart active agent sessions so they reload global instructions and skills.

## Restoring a Backup

Backups preserve the original path below their timestamped directory. To
restore one, remove the replacement symlink, then move the backed-up item to
its original location. Inspect both paths before doing so to avoid overwriting
newer configuration.
