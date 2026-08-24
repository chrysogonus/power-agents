# Shared Coding-Agent Configuration

This repository is the canonical home for personal instructions and reusable
skills shared across Codex and Claude Code.

## Layout

```text
~/power-agents/
├── instructions/
│   └── general-global.md
├── policies/
│   └── codex/
│       └── shared.rules
├── settings/
│   ├── claude/
│   │   └── statusline-command.sh
│   └── codex/
│       └── tui.toml
├── skills/
│   ├── README.md
│   └── <skill-name>/
│       └── SKILL.md
├── install.sh
└── sync.sh
```

The repository contains the only copies of shared instructions and skills.
Most agent-specific configuration paths use symlinks to this repository. Codex
TUI settings are merged into its existing configuration so machine-local state
is preserved.

| Configuration | Installed path | Canonical source | Method |
| --- | --- | --- | --- |
| Codex skills | `~/.agents/skills` | `~/power-agents/skills` | Symlink |
| Claude Code skills | `~/.claude/skills` | `~/power-agents/skills` | Symlink |
| Codex instructions | `~/.codex/AGENTS.md` | `~/power-agents/instructions/general-global.md` | Symlink |
| Claude Code instructions | `~/.claude/CLAUDE.md` | `~/power-agents/instructions/general-global.md` | Symlink |
| Codex authored rules | `~/.codex/rules/shared.rules` | `~/power-agents/policies/codex/shared.rules` | Symlink |
| Claude Code status line | `~/.claude/statusline-command.sh` | `~/power-agents/settings/claude/statusline-command.sh` | Symlink |
| Codex TUI settings | `~/.codex/config.toml` | `~/power-agents/settings/codex/tui.toml` | Managed keys |

Application-managed state, caches, plugins, and bundled skills remain in each
application's own directory and are not managed by this repository. In
particular, Codex continues to own `~/.codex/rules/default.rules` for rules
created through interactive approvals.

## Installation

Clone the repository into `~/power-agents`, then run the installer:

```bash
git clone git@github-personal:chrysogonus/power-rangents.git ~/power-agents
cd ~/power-agents
./install.sh
```

The installer is safe to rerun. For symlink-managed paths, it refuses to replace
real files, directories, or incorrect symlinks. Move any configuration worth
keeping into this repository, remove the conflicting path, and rerun the
installer. The regular `~/.codex/config.toml` file is the exception: the
installer preserves it and updates only the centrally managed TUI keys.

## Syncing

Pull fast-forward updates and reinstall links in one command:

```bash
~/power-agents/sync.sh
```

`sync.sh` uses `git pull --ff-only`, so it stops rather than creating a merge
commit when local and remote history have diverged.

## Quality Checks

The required local checks use Bash, Git, `jq`, and
[ShellCheck](https://www.shellcheck.net/). On Debian or Ubuntu, install the two
non-core tools with:

```bash
sudo apt-get install jq shellcheck
```

Run the same blocking checks as CI with:

```bash
./scripts/check.sh
```

This command parses and statically analyzes every repository shell script,
validates skill metadata, exercises the installer under temporary isolated home
directories, checks the status-line output, and rejects whitespace errors or
unresolved conflict markers. The installer tests never use the invoking user's
home directory. `jq` is already a status-line runtime dependency; ShellCheck is
the only check-specific dependency and is limited to warning-or-higher findings
to avoid subjective style noise.

## Adding or Updating a Skill

See the [skills documentation](skills/README.md) for the current inventory and
skill format. Each skill must live at `skills/<skill-name>/SKILL.md`, and its
frontmatter `name` must exactly match the directory name. Because both agents
link the complete `skills` directory, additions and edits are available without
creating new per-skill links.

## Updating the Authored Command Policy

Edit `policies/codex/shared.rules`. Keep rules created through Codex approval
prompts in the application-managed `~/.codex/rules/default.rules` file.

Test the authored rules against a command with:

```bash
codex execpolicy check --pretty \
  --rules ~/.codex/rules/shared.rules \
  -- .venv/bin/pytest
```

## Updating the Codex Status Line

Edit `settings/codex/tui.toml`, then rerun `./install.sh`. The installer replaces
only `tui.status_line` and `tui.status_line_use_colors` in
`~/.codex/config.toml`; all other Codex settings remain local.

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
