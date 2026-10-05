# Power Agents

**One home for your Codex and Claude Code configuration.**

Keep shared coding instructions, reusable skills, command rules, and status-line
settings in this repository, then install them for both agents with one command.
Edit the source here to keep your setup consistent across projects and machines.

[Quick installation](#installation) · [Skills](skills/README.md) ·
[Customize](#customizing-your-setup) · [Updates](#syncing) ·
[Checks](#quality-checks)

## What You Get

| Included | What it does |
| --- | --- |
| Shared instructions | Gives both agents the same cross-project coding guidelines. |
| 15 reusable skills | Covers code review, task briefs, prompt editing, implementation, frontend design, React, Postgres, and more. [Browse the skills →](skills/README.md) |
| Agent status lines | Configures Claude Code's command-based status line and Codex's terminal status line. |
| Codex command rules | Adds authored approval rules alongside Codex's interactive rules. |

The installer configures **both agents**, even if only one is installed. It does
not install the agents or set up their accounts. Existing unrelated skills and
supported local settings are preserved; [installation details](#installation-details)
explain the managed keys and conflict checks.

## Installation

### ① Prepare your machine

**Supported platform:** GNU/Linux with Bash 4 or newer and GNU coreutils.
macOS is not currently supported; sync and checks use Bash's `mapfile` and GNU
`realpath` behavior.

Install Codex and/or Claude Code separately if you have not already. On Debian
or Ubuntu, install this repository's dependencies:

```bash
sudo apt-get update
sudo apt-get install bash coreutils git make jq python3 python3-tomlkit python3-yaml
```

On other GNU/Linux distributions, install the equivalent packages, including the
Python modules `tomlkit` and PyYAML.

### ② Clone and install

```bash
git clone https://github.com/chrysogonus/power-agents.git ~/power-agents
cd ~/power-agents
make install
```

Prefer SSH? Use `git@github.com:chrysogonus/power-agents.git` as the clone URL
instead. If you already have a checkout, run `make install` from that directory.
The checkout can live elsewhere; the installer uses its actual location.

### ③ Start a new agent session

A successful installation prints `Done.` and lists the canonical source paths.
Restart active agent sessions so they reload global instructions and skills.

To confirm a skill is linked to your checkout:

```bash
readlink ~/.agents/skills/ponytail
```

For the location above, the result ends in `/power-agents/skills/ponytail`.
You can then ask your agent to use a skill, for example:

| Agent | Example prompt |
| --- | --- |
| Codex | `$ponytail fix this bug using the smallest suitable change` |
| Claude Code | `/ponytail fix this bug using the smallest suitable change` |

> **Keep the checkout in place.** Installed instructions, skills, and scripts
> link back to it. Moving or deleting it breaks those links.

If installation reports an existing-path conflict, follow
[Resolving an Installation Conflict](#resolving-an-installation-conflict).

## Customizing Your Setup

Edit files **in this repository**, then run `make install` and `make check`.
Edits to already linked instructions, rules, scripts, and skills are visible
through their links immediately; new skills and managed settings need the
installer to run again. Restart sessions when needed to reload instructions.

| To change… | Edit… |
| --- | --- |
| Shared coding guidelines | [`instructions/general-global.md`](instructions/general-global.md) |
| A skill's instructions or supporting files | `skills/<name>/` — see [Adding or Updating a Skill](#adding-or-updating-a-skill) |
| Codex approval rules | [`policies/codex/shared.rules`](policies/codex/shared.rules) |
| Codex status-line fields and colors | [`settings/codex/tui.toml`](settings/codex/tui.toml) |
| Claude Code status-line display | [`settings/claude/statusline-command.sh`](settings/claude/statusline-command.sh) |

The root `AGENTS.md` and its `CLAUDE.md` symlink contain instructions for working
on this repository. The instructions installed globally come from
`instructions/general-global.md`.

## Commands

Run these from your checkout. `make` alone lists the available commands.

| Command | Purpose |
| --- | --- |
| `make install` | Install or reconcile configuration for both agents. |
| `make sync` | Verify incoming signatures, fast-forward, and reinstall. Requires [trusted signer setup](#syncing). |
| `make test` | Run isolated behavioral tests. |
| `make check` | Validate the current working tree, including behavioral tests. |
| `make ci` | Run checks against the working tree and an archive of `HEAD`. |
| `make eval` | Run opt-in skill evaluations using paid Anthropic API calls. See [setup and costs](#behavioral-skill-evaluations). |

The Make targets delegate to repository scripts, which are also available for
direct use (for example, `./install.sh` and `./scripts/check.sh`).

## Syncing

Use `make sync` to update an installed checkout. It verifies every incoming
commit's OpenPGP signature before updating files or running the installer.
This verification applies to sync updates; the initial clone and installation
above do not perform this signature check.

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
   another machine; see [Contributing](CONTRIBUTING.md#commits-and-pull-requests).

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
├── sync.sh
├── scripts/
├── tests/
└── research/
```

This repository holds the canonical source for shared instructions and skills.
The root `CLAUDE.md` symlink exposes the same repository-specific instructions
as `AGENTS.md`, so Codex and Claude Code use one authoritative project rule set.
Most agent-specific configuration paths use symlinks to this repository. Codex
TUI settings are merged into its existing configuration so machine-local state
is preserved.

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
| Codex authored rules | `<Codex root>/rules/shared.rules` | `policies/codex/shared.rules` | Symlink |
| Claude Code status line | `<Claude root>/statusline-command.sh` | `settings/claude/statusline-command.sh` | Symlink |
| Codex TUI settings | `<Codex root>/config.toml` | `settings/codex/tui.toml` | Managed keys |

Application-managed state, caches, plugins, and bundled skills remain in each
application's own directory and are not managed by this repository. In
particular, Codex continues to own `<Codex root>/rules/default.rules` for rules
created through interactive approvals.

## Installation Details

The installer honors `CODEX_HOME` and `CLAUDE_CONFIG_DIR`; when set, each must
be an absolute directory other than `/`, and the shared, Codex, and Claude roots
must resolve to distinct locations. The installer canonicalizes these paths
before use, so aliases containing `..`, redundant separators, or symlinks cannot
bypass either check. See
the official
[Codex environment-variable reference](https://learn.chatgpt.com/docs/config-file/environment-variables)
and [Claude Code environment-variable reference](https://code.claude.com/docs/en/env-vars).

The installer is safe to rerun with the same checkout and configuration roots.
It preserves unrelated skills in both agents' skill directories, removes stale
per-skill links whose names and targets exactly match links previously created
from this repository, and refuses to replace a
same-name skill, real file, or incorrect symlink. Existing whole-directory skill
links created by an older version of this installer are migrated to per-skill
links. Move any conflicting configuration worth keeping into this repository,
remove the conflicting path, and rerun the installer.

The regular machine-local settings files are exceptions to symlink management.
The installer preserves unrelated values while updating only Claude Code's
`statusLine` key in `<Claude root>/settings.json` and `tui.status_line` and
`tui.status_line_use_colors` in `<Codex root>/config.toml`.
The Codex configuration is parsed and edited
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

Rollback depends on the process being able to run its error or signal handler;
it cannot recover automatically after `SIGKILL`, a process crash, or machine
failure.

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

Rerun `make install` after resolving the reported conflict.

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

`make check` works from either a Git checkout or an exported source archive
without `.git`; `make ci` requires a Git checkout. Installer and agent-runtime
tests never use the invoking user's live configuration.
`jq` is an installer and status-line runtime dependency;
GnuPG is needed for sync signature tests, and ShellCheck is used for static
analysis at warning-or-higher severity.

## Adding or Updating a Skill

See the [skills documentation](skills/README.md) for the current inventory and
skill format. Each skill must live at `skills/<skill-name>/SKILL.md`, and its
frontmatter `name` must exactly match the directory name. Rerun `./install.sh`
after adding a skill so both agents receive its per-skill link. Edits to an
already linked skill are available immediately.

Use `deep-review` for general code reviews. Use `review-report` when findings
should be written to a file, explained for a reader without codebase context,
or provided as paste-ready review comments. Both skills include routing
fixtures in `evals/evals.json`; the checks validate their schema, but do not
execute agent sessions or measure routing pass rates. Run the opt-in evaluations
below to measure their behavior.

The [agent skills research catalog](research/agent-skills-2026-10-05.md) records
upstream candidates, sources, and integration notes. Ten selected skills are
included in the [imported skill inventory](skills/README.md#imported-skills);
their live routing and task-effect evaluations remain unmeasured.

## Behavioral Skill Evaluations

`make eval` runs every case in `skills/*/evals/evals.json` using Claude Code and
grades every assertion in a separate Claude session. This uses paid Anthropic
API calls and is deliberately excluded from `make check` and `make ci`; those
commands test the runner against a fake runtime with no network or credentials.
The runner uses Python 3 and the repository's existing PyYAML dependency.

Set `ANTHROPIC_API_KEY` in your environment without putting it in a command or
file in this repository. For example, in Bash:

```bash
read -rsp 'Anthropic API key: ' ANTHROPIC_API_KEY
printf '\n'
export ANTHROPIC_API_KEY
make eval
unset ANTHROPIC_API_KEY
```

To limit the fixture set or change the defaults:

```bash
make eval EVAL_ARGS='--skill deep-review --repeats 5 --threshold 0.8'
```

<details>
<summary>Evaluation isolation, grading, and runtime details</summary>

All repository skills remain installed during a filtered run, so routing can
select a different skill. Each trial starts with a temporary home, config root,
and working directory. It loads no live user configuration or credentials;
only `ANTHROPIC_API_KEY` is forwarded. Cases get the Skill tool only; this first
runner supports the repository's prompt-only fixture sets. File fixtures
produce an explicit error. The judge has its own empty config and
no tools; it treats prompts, expected outputs, assertions, and transcripts as
untrusted data.

The default is five trials per case and an 80% minimum pass rate. A trial passes
only when a repository skill successfully loads and every assertion passes.
Skill loading is observed through matching Skill calls and successful tool
results, rather than the agent's statements. Judge evidence must quote the
observed response or load record. Failed assertions or missing skill loads count
as failed trials. Runtime, protocol, or judge errors invalidate the run even if
the remaining trials reach the threshold. Missing runtime or environment key
reports `SKIP`; it never reports `PASS`.

Results go to the gitignored `eval-results/<run-id>/results.json` and `summary.md`,
including per-case pass rates, each assertion's grade and evidence, redacted
runtime transcripts, actual model names, runtime version, and source-file hashes.
Exit codes are 0 for passing cases, 1 for a case below threshold, and 2 for
`SKIP`, operational errors, or invalid arguments. Result directories are private
and an existing result directory is never overwritten.

CLI flags were checked against Claude Code 2.1.226's help and installed protocol.
The runner also checks required flags before a credentialed run. It uses normal
headless mode to preserve automatic skill discovery, restricts setting sources
to its isolated user config, disables hooks, and supplies an empty MCP config.
Sessions have a 180-second timeout and a $1 API budget cap each. Use `--model`,
`--judge-model`, `--timeout`, `--runtime`, or `--output-dir` through `EVAL_ARGS`
when needed; `python3 scripts/run-evals.py --help` lists all options. Codex is not
supported as an evaluation runtime yet.

</details>

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

In `<Claude root>/settings.json`, remove the `statusLine` key if it still points
to this repository's status-line script, or restore your own status-line setting.
Keep all other settings. The installer does not retain a backup of earlier
managed values after a successful run. Once the links and managed settings are
removed, the checkout can be removed separately.

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
