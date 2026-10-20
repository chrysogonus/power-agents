# Installation Reference

This page explains exactly what `make install` and `make sync` change on your
machine, how to resolve installer conflicts, and how to uninstall. For the
quick start, see the [README](../README.md#installation).

## Installed Paths

In the table below, *Codex root* means the directory selected by `CODEX_HOME`,
or `~/.codex` when it is unset. *Claude root* means the directory selected by
`CLAUDE_CONFIG_DIR`, or `~/.claude` when it is unset. The shared Codex skill
directory remains `~/.agents/skills`, even when `CODEX_HOME` is set.

| Configuration | Installed path | Source relative to checkout | Method |
| --- | --- | --- | --- |
| Codex skills | `~/.agents/skills/<name>` | `skills/<name>` | Per-skill symlink |
| Claude Code skills | `<Claude root>/skills/<name>` | `skills/<name>` | Per-skill symlink |
| Codex instructions | `<Codex root>/AGENTS.md` | `instructions/general-global.md` | Symlink |
| Claude Code instructions | `<Claude root>/CLAUDE.md` | `instructions/general-global.md` | Symlink |
| Claude Code settings | `<Claude root>/settings.json` | `settings/claude/settings.json` | Managed keys |
| Claude Code verify-gate hooks | `<Claude root>/settings.json` (`hooks`) | `settings/claude/hooks.json` | Managed entries |
| Codex authored rules | `<Codex root>/rules/shared.rules` | `policies/codex/shared.rules` | Symlink |
| Claude Code status line | `<Claude root>/statusline-command.sh` | `settings/claude/statusline-command.sh` | Symlink |
| Codex TUI settings | `<Codex root>/config.toml` | `settings/codex/tui.toml` | Managed keys |
| Codex verify-gate hooks | `<Codex root>/hooks.json` | `settings/codex/hooks.json` | Managed entries |
| Verify gate script | `~/.agents/hooks/verify-gate.py` | `hooks/verify-gate.py` | Symlink |

Application-managed state, caches, plugins, and bundled skills remain in each
application's own directory and are not managed by this repository. In
particular, Codex continues to own `<Codex root>/rules/default.rules` for rules
created through interactive approvals.

## Installation Details

The installer honors `CODEX_HOME` and `CLAUDE_CONFIG_DIR`; when set, each must
be an absolute directory other than `/`, and the shared, Codex, and Claude roots
must resolve to distinct locations. The installer canonicalizes these paths
before use, so aliases containing `..`, redundant separators, or symlinks cannot
bypass either check. See the official
[Codex environment-variable reference](https://learn.chatgpt.com/docs/config-file/environment-variables)
and [Claude Code environment-variable reference](https://code.claude.com/docs/en/env-vars).

The installer is safe to rerun with the same checkout and configuration roots.
It preserves unrelated skills in both agents' skill directories, removes stale
per-skill links whose names and targets exactly match links previously created
from this repository, and refuses to replace a same-name skill, real file, or
incorrect symlink. Existing whole-directory skill links created by an older
version of this installer are migrated to per-skill links. Move any conflicting
configuration worth keeping into this repository, remove the conflicting path,
and rerun the installer.

The regular machine-local settings files are exceptions to symlink management.
The installer preserves unrelated values while updating only Claude Code's
`statusLine` key in `<Claude root>/settings.json`, `tui.status_line` and
`tui.status_line_use_colors` in `<Codex root>/config.toml`, and the verify-gate
hook entries in `<Claude root>/settings.json` and `<Codex root>/hooks.json`.
Hook entries are reconciled one handler at a time: handlers whose command
references `~/.agents/hooks/verify-gate.py` are replaced, and every other hook,
matcher group, and event is kept. The installer refuses a symlinked or invalid
`<Codex root>/hooks.json`, and refuses either file while it still contains a
legacy standalone `verify_gate.py` hook.

The Codex configuration is parsed and edited with a format-preserving TOML
library. Before activation, the installer prepares and validates all complete
settings files. Once activation begins, a surfaced failure rolls back files,
links, and directories created or replaced during that run, restoring the
pre-install configuration.

Claude settings are reconciled with `jq`, which represents JSON numbers as
double-precision values. Numeric values that cannot be represented exactly may
therefore be rounded when `settings.json` is rewritten; this includes integers
with a magnitude greater than `9007199254740991`. Preservation applies to
`jq`-representable semantic values, not original JSON formatting or arbitrary
numeric precision.

Rollback depends on the process being able to run its error or signal handler;
it cannot recover automatically after `SIGKILL`, a process crash, or machine
failure.

## Project Instructions in Claude Code

Codex and Claude Code use this repository's root `AGENTS.md` for
repository-specific instructions. Direct loading in Claude Code requires version
2.1.277 or newer with its built-in `AGENTS.md` support enabled. This repository
has no root `CLAUDE.md` compatibility link for older versions.

By default, a project or ancestor `CLAUDE.md`, `.claude/CLAUDE.md`, or
`CLAUDE.local.md` takes precedence over `AGENTS.md` in Claude Code. If you keep
one of those files, set **Project instructions** in `/config` to
`claude-md-and-agents-md` to load both. Check `/context` in a fresh session to
confirm the project instructions loaded. See
[Claude Code's AGENTS.md documentation](https://code.claude.com/docs/en/memory#agentsmd).

The installer still links the shared global instructions to
`<Claude root>/CLAUDE.md`; Claude's user-wide instruction entrypoint remains
separate from project `AGENTS.md` discovery.

## Resolving an Installation Conflict

The installer never moves or deletes conflicting user data. It replaces a legacy
whole-directory skill link when that link resolves to this repository and
removes stale per-skill links that exactly match links it previously created.

Inspect the path named in the error and keep a backup before changing it:

| Installer message | What to do |
| --- | --- |
| `Refusing to replace existing path` | Merge instructions or skill content you want to keep into the corresponding repository source, then remove the conflicting path. |
| `Refusing to update symlinked Claude settings` or `Refusing to update symlinked Codex config` | Replace the settings symlink with a regular file containing your existing settings. |
| Invalid Claude settings or invalid/unsupported Codex config | Fix the local JSON or TOML file; keep unrelated settings there. |
| `Duplicate Codex skill exists` | Reconcile the named skill with its repository copy, then remove that duplicate from `<Codex root>/skills/`. Leave unrelated skills in place. |
| `legacy standalone verify gate hook` | Run the standalone verify gate's `uninstall.sh`, which removes its `~/.agent-hooks/verify_gate.py` hooks. |
| `Refusing to update symlinked Codex hooks` or invalid/unsupported hooks | Replace `<Codex root>/hooks.json` with a regular file, or fix its JSON and hook layout. |

Rerun `make install` after resolving the reported conflict.

## Syncing

Use `make sync` to update an installed checkout. It verifies every incoming
commit's OpenPGP signature before updating files or running the installer.
This verification applies to sync updates; the initial clone and installation
do not perform this signature check.

### Set up trusted signers once

1. Install GnuPG (`sudo apt-get install gnupg` on Debian or Ubuntu).
2. Obtain and import the public keys of the people whose signed commits you
   intend to accept. Confirm their full primary-key fingerprints through a
   trusted channel; `gpg --fingerprint` lists fingerprints for imported keys.
3. Create an allowlist **outside this repository**, at the path used by sync:

   ```bash
   mkdir -p ~/.config/power-agents
   ${EDITOR:-vi} ~/.config/power-agents/trusted-signing-keys
   ```

   Add one trusted full primary-key fingerprint per line. Blank lines and lines
   starting with `#` are ignored. If you create your own commits, configure
   OpenPGP signing and include your key when those commits will be synced to
   another machine; see [Contributing](../CONTRIBUTING.md#commits-and-pull-requests).

### Update your checkout

```bash
make -C ~/power-agents sync
```

`sync.sh` fetches the current branch's configured upstream, verifies every
commit in the incoming range with `git verify-commit`, then fast-forwards and
reruns the installer. It requires each primary-key fingerprint to appear in the
allowlist and rejects unsigned, invalid, expired, revoked, or unlisted
signatures and divergent history without changing `HEAD` or running incoming
code. An up-to-date checkout may still rerun the already-trusted installer.

Sync requires a working tree with no tracked or staged changes; untracked files
are preserved. If the incoming installer fails after a fast-forward, or sync
receives a handled signal during activation, sync restores the previous commit
and reruns its installer to restore the prior configuration. This recovery
cannot run after `SIGKILL`, a process crash, or machine failure.

## Updating the Codex Status Line

Edit `settings/codex/tui.toml`, then rerun `./install.sh`. The installer replaces
only `tui.status_line` and `tui.status_line_use_colors` in
`<Codex root>/config.toml`; all other Codex settings remain local.

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

## Manual Uninstall

There is no automated uninstaller. Before removing anything, use `readlink` to
verify that each managed symlink in the [installed-paths table](#installed-paths)
resolves into this checkout. Use `unlink` only on verified links, including each
repository-owned entry under `~/.agents/skills/` and `<Claude root>/skills/`;
keep those directories and all unrelated skills intact. Older installations may
instead have a verified whole-directory `skills` symlink, which can be unlinked
as one path.

Next, edit `<Codex root>/config.toml` and remove `status_line` and
`status_line_use_colors` from `[tui]` if those managed values are no longer
wanted. Keep the `[tui]` table when it contains other local settings.

In `<Claude root>/settings.json`, remove the `statusLine` key if it still points
to this repository's status-line script, or restore your own status-line setting.
Keep all other settings. The installer does not retain a backup of earlier
managed values after a successful run.

Remove the verify-gate hook entries from both files, check the results, and only
then replace the originals. Run this from the checkout, substituting your roots if
`CLAUDE_CONFIG_DIR` or `CODEX_HOME` is set:

```bash
python3 scripts/reconcile-hooks.py remove \
  ~/.claude/settings.json ~/.claude/settings.json.new
python3 scripts/reconcile-hooks.py remove \
  ~/.codex/hooks.json ~/.codex/hooks.json.new
```

Only handlers that reference `~/.agents/hooks/verify-gate.py` are removed, along
with any matcher group, event, or `hooks` object that becomes empty as a result.
Review each `.new` file, then move it over the original. Finally, verify
`~/.agents/hooks/verify-gate.py` with `readlink` and `unlink` it. Once the links
and managed settings are removed, the checkout can be removed separately.
