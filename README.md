# Shared Coding-Agent Configuration

This repository is the canonical home for personal instructions and reusable
skills shared across Codex and Claude Code.

## Layout

```text
~/power-agents/
├── AGENTS.md
├── CLAUDE.md -> AGENTS.md
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
The root `CLAUDE.md` symlink exposes the same repository-specific instructions
as `AGENTS.md`, so Codex and Claude Code use one authoritative project rule set.
Most agent-specific configuration paths use symlinks to this repository. Codex
TUI settings are merged into its existing configuration so machine-local state
is preserved.

In the table below, *Codex root* means the directory selected by `CODEX_HOME`,
or `~/.codex` when it is unset. *Claude root* means the directory selected by
`CLAUDE_CONFIG_DIR`, or `~/.claude` when it is unset. The shared Codex skill
directory remains `~/.agents/skills`.

| Configuration | Installed path | Canonical source | Method |
| --- | --- | --- | --- |
| Codex skills | `~/.agents/skills/<name>` | `~/power-agents/skills/<name>` | Per-skill symlink |
| Claude Code skills | `<Claude root>/skills/<name>` | `~/power-agents/skills/<name>` | Per-skill symlink |
| Codex instructions | `<Codex root>/AGENTS.md` | `~/power-agents/instructions/general-global.md` | Symlink |
| Claude Code instructions | `<Claude root>/CLAUDE.md` | `~/power-agents/instructions/general-global.md` | Symlink |
| Claude Code settings | `<Claude root>/settings.json` | `~/power-agents/settings/claude/settings.json` | Managed keys |
| Codex authored rules | `<Codex root>/rules/shared.rules` | `~/power-agents/policies/codex/shared.rules` | Symlink |
| Claude Code status line | `<Claude root>/statusline-command.sh` | `~/power-agents/settings/claude/statusline-command.sh` | Symlink |
| Codex TUI settings | `<Codex root>/config.toml` | `~/power-agents/settings/codex/tui.toml` | Managed keys |

Application-managed state, caches, plugins, and bundled skills remain in each
application's own directory and are not managed by this repository. In
particular, Codex continues to own `<Codex root>/rules/default.rules` for rules
created through interactive approvals.

## Installation

This repository supports GNU/Linux with Bash 4 or newer and GNU coreutils.
macOS is not currently supported: the authenticated sync and quality-check
scripts rely on Bash's `mapfile` and GNU `realpath` behavior.

On Debian or Ubuntu, install the tools needed for a fresh installation first:

```bash
sudo apt-get install bash coreutils git make jq python3 python3-tomlkit python3-yaml
```

Then clone the repository into `~/power-agents` and run the installer:

```bash
git clone git@github-personal:chrysogonus/power-agents.git ~/power-agents
cd ~/power-agents
make install
```

The installer honors Codex's documented `CODEX_HOME` and Claude Code's
documented `CLAUDE_CONFIG_DIR`; when set, each must be an absolute directory
other than `/`, and the shared, Codex, and Claude roots must be distinct. See the
official
[Codex environment-variable reference](https://learn.chatgpt.com/docs/config-file/environment-variables)
and [Claude Code environment-variable reference](https://code.claude.com/docs/en/env-vars).

The installer is safe to rerun. It preserves unrelated skills in both agents'
skill directories, removes stale per-skill links whose names and targets exactly
match links previously created from this repository, and refuses to replace a
same-name skill, real file, or incorrect symlink. Existing whole-directory skill
links created by an older version of this installer are migrated to per-skill
links. Move any conflicting configuration worth keeping into this repository,
remove the conflicting path, and rerun the installer.

The regular machine-local settings files are exceptions to symlink management.
The installer preserves unrelated values while updating only Claude Code's
`statusLine` key in `<Claude root>/settings.json` and the centrally managed TUI
keys in `<Codex root>/config.toml`. The Codex configuration is parsed and edited
with a format-preserving TOML library. Before activation, the installer prepares
and validates both complete settings files. Once activation begins, a surfaced
failure rolls back files, links, and directories created or replaced during
that run, restoring the pre-install configuration.

Claude settings are reconciled with `jq`, which represents JSON numbers as
double-precision values. Numeric values that cannot be represented exactly may
therefore be rounded when `settings.json` is rewritten; this includes integers
with a magnitude greater than `9007199254740991`. Preservation applies to
`jq`-representable semantic values, not original JSON formatting or arbitrary
numeric precision.

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
make check    # Run checks against the current working tree
make ci       # Run the same complete pipeline as GitHub Actions
```

The Make targets delegate to the repository scripts, which remain available for
direct use.

## Security

The [Security Policy](SECURITY.md) describes the supported version, the trust
model enforced by `sync.sh`, and how to report a suspected vulnerability
privately. Do not open a public issue for one.

## Contributing

See [Contributing](CONTRIBUTING.md) for the required workflow and the
[Code of Conduct](CODE_OF_CONDUCT.md) for participation expectations.

## License

Original repository content is available under the [MIT License](LICENSE).
Third-party components retain their respective terms and attribution; see
[Third-Party Notices](THIRD_PARTY_NOTICES.md).

## Quality Checks

The core local checks use Make, Bash, Git, GnuPG, `jq`, Python 3 with `tomlkit`
and PyYAML, and
[ShellCheck](https://www.shellcheck.net/). On Debian or Ubuntu, install the
dependencies with:

```bash
sudo apt-get install make gnupg jq python3 python3-tomlkit python3-yaml shellcheck
```

Run the complete pipeline locally after committing and before pushing:

```bash
make ci
```

`make ci` runs the checks once against the current working tree and once against
a source archive of `HEAD`. During development, use `make check` to run only the
faster working-tree pass.

The checks parse and statically analyze every repository shell script, validate
skill metadata, exercise settings reconciliation and the installer under
temporary isolated home directories, check the status-line output, and reject
whitespace errors or unresolved conflict markers. If `codex` is installed, the
tests ask it to parse the managed TUI configuration and evaluate every authored
command rule. If `claude` is installed, the tests run `claude doctor` against an
isolated installed configuration and reject any invalid-settings report. Both
checks also feed their runtime a known-invalid setting to prove that the
validation path is active. A missing local runtime is reported as `SKIP`, never
`PASS`. GitHub Actions installs the current npm releases of both agents and
requires both compatibility checks; use
`POWER_AGENTS_REQUIRE_AGENT_RUNTIMES=1 make ci` for the same requirement locally.

The checks work from either a Git checkout or an exported source archive without
`.git`. Installer and agent-runtime tests never use the invoking user's live
configuration. `jq` is an installer and status-line runtime dependency;
ShellCheck is the only check-specific dependency and is limited to
warning-or-higher findings to avoid subjective style noise.

## Adding or Updating a Skill

See the [skills documentation](skills/README.md) for the current inventory and
skill format. Each skill must live at `skills/<skill-name>/SKILL.md`, and its
frontmatter `name` must exactly match the directory name. Rerun `./install.sh`
after adding a skill so both agents receive its per-skill link. Edits to an
already linked skill are available immediately.

## Updating the Authored Command Policy

Edit `policies/codex/shared.rules`. Keep rules created through Codex approval
prompts in the application-managed `<Codex root>/rules/default.rules` file.

Test the authored rules against a command with:

```bash
codex execpolicy check --pretty \
  --rules "${CODEX_HOME:-$HOME/.codex}/rules/shared.rules" \
  -- .venv/bin/pytest
```

The shared policy prompts for common relative virtual-environment pytest
executables, `python`/`python3 -m pytest`, and relative virtual-environment
Python launchers. Prefix rules match literal argument prefixes, so they cannot
exhaustively cover virtual environments invoked through arbitrary absolute
paths.

## Updating the Codex Status Line

Edit `settings/codex/tui.toml`, then rerun `./install.sh`. The installer replaces
only `tui.status_line` and `tui.status_line_use_colors` in
`<Codex root>/config.toml`; all other Codex settings remain local.

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

The installer never moves or deletes conflicting user data. It replaces a legacy
whole-directory skill link when that link resolves to this repository and
removes stale per-skill links that exactly match links it previously created.
Inspect the path named in any error, move configuration worth keeping into this
repository, then remove the conflict and rerun `./install.sh`.

## Manual Uninstall

There is no automated uninstaller. Before removing anything, use `readlink` to
verify that each managed symlink in the table above resolves into this checkout.
Use `unlink` only on verified links, including each repository-owned entry under
`~/.agents/skills/` and `<Claude root>/skills/`; keep those directories and all
unrelated skills intact. Older installations may instead have a verified
whole-directory `skills` symlink, which can be unlinked as one path.

Finally, edit `<Codex root>/config.toml` and remove `status_line` and
`status_line_use_colors` from `[tui]` if those managed values are no longer
wanted. Keep the `[tui]` table when it contains other local settings.
