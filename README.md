# Shared Coding-Agent Configuration

This repository is the canonical home for personal instructions and reusable
skills shared across Codex and Claude Code.

## Layout

```text
~/power-agents/
├── instructions/
│   └── general-global.md
├── skills/
│   ├── README.md
│   └── <skill-name>/
│       └── SKILL.md
├── install.sh
└── sync.sh
```

The repository contains the only copies of shared instructions and skills.
Agent-specific configuration paths use symlinks to this repository:

| Agent | Installed path | Canonical target |
| --- | --- | --- |
| Codex skills | `~/.agents/skills` | `~/power-agents/skills` |
| Claude Code skills | `~/.claude/skills` | `~/power-agents/skills` |
| Codex instructions | `~/.codex/AGENTS.md` | `~/power-agents/instructions/general-global.md` |
| Claude Code instructions | `~/.claude/CLAUDE.md` | `~/power-agents/instructions/general-global.md` |

Application-managed state, caches, plugins, and bundled skills remain in each
application's own directory and are not managed by this repository.

## Installation

Clone the repository into `~/power-agents`, then run the installer:

```bash
git clone git@github-personal:chrysogonus/power-rangents.git ~/power-agents
cd ~/power-agents
./install.sh
```

The installer is safe to rerun. It refuses to replace real files, directories,
or incorrect symlinks. Move any configuration worth keeping into this
repository, remove the conflicting path, and rerun the installer. This
fail-fast behavior prevents backup copies from becoming competing sources of
truth.

## Syncing

Pull fast-forward updates and reinstall links in one command:

```bash
~/power-agents/sync.sh
```

`sync.sh` uses `git pull --ff-only`, so it stops rather than creating a merge
commit when local and remote history have diverged.

## Adding or Updating a Skill

See the [skills documentation](skills/README.md) for the current inventory and
skill format. Each skill must live at `skills/<skill-name>/SKILL.md`, and its
frontmatter `name` must exactly match the directory name. Because both agents
link the complete `skills` directory, additions and edits are available without
creating new per-skill links.

## New-Machine Setup

1. Install the agents you use and Git.
2. Configure SSH access for the `github-personal` host alias, or clone with an
   HTTPS URL and update the remote as needed.
3. Clone this repository to `~/power-agents`.
4. Optionally configure the repository-local Git identity:

   ```bash
   git config --local user.name "Your Name"
   git config --local user.email "your-address@example.com"
   ```

5. Run `./install.sh`.
6. Restart active agent sessions so they reload global instructions and skills.

## Resolving an Installation Conflict

The installer never moves or deletes conflicting data. Inspect the path named
in the error, move any configuration worth keeping into this repository, then
remove the conflict and rerun `./install.sh`.
