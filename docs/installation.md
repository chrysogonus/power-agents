# Installation Reference

This page explains exactly what `make install` and `make sync` change on your
machine, how to resolve installer conflicts, and how to uninstall. For the
quick start, see the [README](../README.md#installation).

## Installed Paths

In the table below, *Codex root* means the directory selected by `CODEX_HOME`,
or `~/.codex` when it is unset. *Claude root* means the directory selected by
`CLAUDE_CONFIG_DIR`, or `~/.claude` when it is unset. The shared Codex skill
directory remains `~/.agents/skills`, even when `CODEX_HOME` is set.

| Component | Configuration | Installed path | Source relative to checkout | Method |
| --- | --- | --- | --- | --- |
| always | Claude Code verify-gate hooks | `<Claude root>/settings.json` (`hooks`) | `settings/claude/hooks.json` | Managed entries |
| always | Codex verify-gate hooks | `<Codex root>/hooks.json` | `settings/codex/hooks.json` | Managed entries |
| always | Verify gate script | `~/.agents/hooks/verify-gate.py` | `hooks/verify-gate.py` | Symlink |
| always | Component selection | `~/.config/power-agents/components` | none | Written by the installer |
| `instructions` | Codex instructions | `<Codex root>/AGENTS.md` | `instructions/general-global.md` | Symlink |
| `instructions` | Claude Code instructions | `<Claude root>/CLAUDE.md` | `instructions/general-global.md` | Symlink |
| `skills` | Codex skills | `~/.agents/skills/<name>` | `skills/<name>` | Per-skill symlink |
| `skills` | Claude Code skills | `<Claude root>/skills/<name>` | `skills/<name>` | Per-skill symlink |
| `statusline` | Claude Code settings | `<Claude root>/settings.json` | `settings/claude/settings.json` | Managed keys |
| `statusline` | Claude Code status line | `<Claude root>/statusline-command.sh` | `settings/claude/statusline-command.sh` | Symlink |
| `statusline` | Codex TUI settings | `<Codex root>/config.toml` | `settings/codex/tui.toml` | Managed keys |
| `statusline` | Installed Codex TUI values | `~/.config/power-agents/codex-tui.toml` | `settings/codex/tui.toml` | Copy |
| `codex-rules` | Codex authored rules | `<Codex root>/rules/shared.rules` | `policies/codex/shared.rules` | Symlink |

Application-managed state, caches, plugins, and bundled skills remain in each
application's own directory and are not managed by this repository. In
particular, Codex continues to own `<Codex root>/rules/default.rules` for rules
created through interactive approvals.

## Choosing Components

The verify gate is always installed. Select optional components with
`./install.sh --components LIST`, where `LIST` is a comma-separated subset of
`instructions`, `skills`, `statusline`, and `codex-rules`, or `all` or `none`.
An unknown name fails before anything changes.

- **The selection is saved.** The installer writes it to
  `~/.config/power-agents/components`, together with the Codex and Claude roots
  it was installed into, as the last step of a successful install; a failed
  install leaves the previous file in place. Without `--components`,
  `make install`, `make sync`, and sync's own recovery reuse the saved
  selection.
- **Without a saved selection for the current roots**, the installer keeps what
  is already installed there: it treats each optional component whose links
  already point into this checkout as selected, and saves that. This covers
  upgrades from installs made before components existed, and switching
  `CODEX_HOME` or `CLAUDE_CONFIG_DIR` between profiles. A saved selection is
  never applied to roots it was not saved for.
- **Deselecting a component removes only what the installer added for it.** It
  unlinks only links that resolve into this checkout. For `statusline`, it
  removes Claude Code's `statusLine` while its command still runs this
  checkout's script through the installed link, even if you added fields such as
  `padding`. It removes Codex's `tui.status_line` and
  `tui.status_line_use_colors` only while they still hold the values the
  installer wrote, which it saves in `~/.config/power-agents/codex-tui.toml`,
  and only when the saved selection was recorded for the current Codex and
  Claude roots, because those keys carry no other proof of ownership. Changes
  to `settings/codex/tui.toml` since that install do not affect what is
  removed. Otherwise they stay, and values you changed always stay. Directories such as
  `~/.agents/skills` and `<Codex root>/rules` are kept. The removal runs only
  when a component changes from selected to deselected, so a status-line script
  of your own at `<Claude root>/statusline-command.sh` is never touched by an
  install that does not select `statusline`.
- **Some paths are shared by every profile.** Codex reads `~/.agents/skills`
  whatever `CODEX_HOME` is, and both agents run the gate from
  `~/.agents/hooks/verify-gate.py`. Deselecting `skills` for one profile
  removes the shared Codex skill links; the next install for a profile that
  still selects `skills` restores them.
- **Python modules are needed only by their component.** `statusline` needs
  `tomlkit`, also for removing it, and `skills` needs PyYAML for validation. A
  gate-only install needs neither.

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
The installer preserves unrelated values while updating only the verify-gate
hook entries in `<Claude root>/settings.json` and `<Codex root>/hooks.json`,
and, with the `statusline` component, Claude Code's `statusLine` key in
`<Claude root>/settings.json` and `tui.status_line` and
`tui.status_line_use_colors` in `<Codex root>/config.toml`. Without
`statusline`, it does not create or change `<Codex root>/config.toml`.
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

With the `instructions` component, the installer links the shared global
instructions to `<Claude root>/CLAUDE.md`; Claude's user-wide instruction
entrypoint remains separate from project `AGENTS.md` discovery.

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

Use `make sync` to update an installed checkout:

```bash
make -C ~/power-agents sync
```

`sync.sh` fetches the current branch's configured upstream, fast-forwards to
it, and reruns the installer. It does not check commit signatures: anyone who
can push to the upstream controls the code that sync installs, including the
verify gate both agents run as a hook. Divergent history is rejected without
changing `HEAD`. An up-to-date checkout still reruns the installer.

Sync requires a working tree with no tracked or staged changes; untracked files
are preserved. If the incoming installer fails after a fast-forward, or sync
receives a handled signal during activation, sync restores the previous commit
and reruns its installer to restore the prior configuration. This recovery
cannot run after `SIGKILL`, a process crash, or machine failure.

Checkouts whose `sync.sh` still verifies signatures reject the unsigned
commits that removed that check. Update such a checkout once by hand, then
use `make sync` again:

```bash
git -C ~/power-agents pull --ff-only
~/power-agents/install.sh
```

## Updating the Codex Status Line

Edit `settings/codex/tui.toml`, then rerun `./install.sh` with the `statusline`
component selected. The installer replaces
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

## Uninstall

```bash
make uninstall   # or: ./install.sh --uninstall
```

This removes, for the agent roots selected by `CODEX_HOME` and
`CLAUDE_CONFIG_DIR`:

- every optional component, exactly as `./install.sh --components none` does:
  it unlinks only links that resolve into this checkout, and removes managed
  status-line values only while they are unchanged;
- the verify-gate entries in `<Claude root>/settings.json` and
  `<Codex root>/hooks.json`, along with any matcher group, event, or `hooks`
  object that becomes empty as a result. Every other setting and hook is kept;
- the `~/.agents/hooks/verify-gate.py` link, if it points into this checkout;
- `~/.config/power-agents/components` and `~/.config/power-agents/codex-tui.toml`.

It refuses to run when `~/.agents/hooks/verify-gate.py` belongs to another
checkout; run it from that checkout instead. When the saved selection in
`~/.config/power-agents/components` belongs to other agent roots, it removes
only these roots' hook entries and links, and keeps the shared gate link and
that saved state, which the other install still uses.

It keeps the cross-review toggle (`~/.config/power-agents/cross-review-on`),
your [per-project settings](verify-gate.md#per-project-settings)
(`~/.config/power-agents/projects.json`), and the gate's decision log and state
in `~/.cache/verify-gate`; delete those by hand if you want them gone. It does not restore a status-line setting you had
before installing `statusline`, because the installer keeps no backup of
earlier managed values. It creates no files, and running it again changes
nothing. Like an install, it rolls back if it fails partway. Once it is done,
the checkout can be removed separately.
