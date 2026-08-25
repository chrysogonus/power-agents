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
│   │   ├── settings.json
│   │   └── statusline-command.sh
│   └── codex/
│       └── tui.toml
├── skills/
│   ├── README.md
│   └── <skill-name>/
│       └── SKILL.md
├── Makefile
├── install.sh
└── sync.sh
```

The repository contains the only copies of shared instructions and skills.
Most agent-specific configuration paths use symlinks to this repository. Codex
TUI settings are merged into its existing configuration so machine-local state
is preserved.

| Configuration | Installed path | Canonical source | Method |
| --- | --- | --- | --- |
| Codex skills | `~/.agents/skills/<name>` | `~/power-agents/skills/<name>` | Per-skill symlink |
| Claude Code skills | `~/.claude/skills/<name>` | `~/power-agents/skills/<name>` | Per-skill symlink |
| Codex instructions | `~/.codex/AGENTS.md` | `~/power-agents/instructions/general-global.md` | Symlink |
| Claude Code instructions | `~/.claude/CLAUDE.md` | `~/power-agents/instructions/general-global.md` | Symlink |
| Claude Code settings | `~/.claude/settings.json` | `~/power-agents/settings/claude/settings.json` | Managed keys |
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
git clone git@github-personal:chrysogonus/power-agents.git ~/power-agents
cd ~/power-agents
make install
```

The installer is safe to rerun. It preserves unrelated skills in both agents'
skill directories and refuses to replace a same-name skill, real file, or
incorrect symlink. Existing whole-directory skill links created by an older
version of this installer are migrated to per-skill links. Move any conflicting
configuration worth keeping into this repository, remove the conflicting path,
and rerun the installer.

The regular machine-local settings files are exceptions to symlink management.
The installer preserves unrelated values while updating only Claude Code's
`statusLine` key in `~/.claude/settings.json` and the centrally managed TUI keys
in `~/.codex/config.toml`. An existing Codex TUI configuration must use an
explicit `[tui]` table; top-level `tui.status_line = ...` and `tui = {...}` forms
are rejected before installation because appending another `[tui]` table would
produce invalid TOML.

## Syncing

Sync verifies every incoming commit before updating the working tree or running
the installer. Configure Git to sign commits with your OpenPGP key, then put the
key's full primary fingerprint in an allowlist outside this repository:

```bash
git config --local gpg.format openpgp
git config --local commit.gpgsign true
gpg --fingerprint "$(git config user.signingkey)"
mkdir -p ~/.config/power-agents
${EDITOR:-vi} ~/.config/power-agents/trusted-signing-keys
```

The allowlist accepts one full fingerprint per line; blank lines and lines
starting with `#` are ignored. Once it is configured, fetch, verify,
fast-forward, and reinstall in one command:

```bash
make -C ~/power-agents sync
```

`sync.sh` verifies every commit in the incoming range with `git verify-commit`
and requires its primary-key fingerprint to appear in the external allowlist.
It rejects unsigned, invalid, expired, revoked, or unlisted signatures and
divergent history without changing `HEAD` or running incoming code. An
up-to-date checkout may still rerun the already-trusted installer.

## Commands

Run `make` to list the available commands:

```text
make install  # Install the agent configuration
make sync     # Verify, fast-forward, and reinstall the configuration
make test     # Run the isolated behavioral tests
make check    # Run all required repository checks
```

The Make targets delegate to the repository scripts, which remain available for
direct use.

## Quality Checks

The required local checks use Make, Bash, Git, GnuPG, `jq`, and
[ShellCheck](https://www.shellcheck.net/). On Debian or Ubuntu, install the
dependencies with:

```bash
sudo apt-get install make gnupg jq shellcheck
```

Run the same blocking checks as CI with:

```bash
make check
```

This command parses and statically analyzes every repository shell script,
validates skill metadata, exercises settings reconciliation and the installer
under temporary isolated home directories, checks the status-line output, and
rejects whitespace errors or unresolved conflict markers. It works from either
a Git checkout or an exported source archive without `.git`. The installer tests
never use the invoking user's home directory. `jq` is an installer and
status-line runtime dependency; ShellCheck is the only check-specific dependency
and is limited to warning-or-higher findings to avoid subjective style noise.

## Adding or Updating a Skill

See the [skills documentation](skills/README.md) for the current inventory and
skill format. Each skill must live at `skills/<skill-name>/SKILL.md`, and its
frontmatter `name` must exactly match the directory name. Rerun `./install.sh`
after adding a skill so both agents receive its per-skill link. Edits to an
already linked skill are available immediately.

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

5. Run `make install`.
6. Restart active agent sessions so they reload global instructions and skills.

## Resolving an Installation Conflict

The installer never moves or deletes conflicting user data. It only replaces a
legacy whole-directory skill link when that link resolves to this repository.
Inspect the path named in any error, move configuration worth keeping into this
repository, then remove the conflict and rerun `./install.sh`.

## Manual Uninstall

There is no automated uninstaller. Before removing anything, use `readlink` to
verify that each managed symlink in the table above resolves into this checkout.
Use `unlink` only on verified links, including each repository-owned entry under
`~/.agents/skills/` and `~/.claude/skills/`; keep those directories and all
unrelated skills intact. Older installations may instead have a verified
whole-directory `skills` symlink, which can be unlinked as one path.

Finally, edit `~/.codex/config.toml` and remove `status_line` and
`status_line_use_colors` from `[tui]` if those managed values are no longer
wanted. Keep the `[tui]` table when it contains other local settings.
