# Power Agents

**One place to keep your setup for the coding agents Codex and Claude Code.**

Coding agents read their setup from hidden folders in your home directory
(`~/.codex`, `~/.claude`). If you use both agents, or work on more than one
machine, those folders drift apart quickly. Power Agents keeps all of that setup
in one Git repository and installs it for **both agents with one command**.

You edit files here, run `make install`, and both agents pick up the same
instructions and skills.

## What You Get

| Feature | What it means for you |
| --- | --- |
| **Shared instructions** | Both agents follow the same personal coding preferences in every project ([`instructions/general-global.md`](instructions/general-global.md)). |
| **13 skills** | Ready-made guides for specific jobs, such as minimal bug fixes, code reviews, React, Postgres, security, and UI design. [Browse the skills →](skills/README.md) |
| **Self-check before answering** | When the agent changes files or writes a long answer, it is sent back once to check its work against the files, tests, or docs. Optionally, the *other* agent reviews it too. [Details →](docs/verify-gate.md) |
| **Status lines** | Both agents show the project, model, context used, and usage limits at the bottom of the terminal. |
| **Codex command rules** | Codex asks before running some test commands (`pytest` from a virtual environment, `python -m pytest`). |

Power Agents does **not** install Codex or Claude Code themselves, and does not
set up their accounts.

## How It Works

```text
  this repository                       your home directory
  ───────────────                       ───────────────────
  instructions/general-global.md ──▶ ~/.codex/AGENTS.md, ~/.claude/CLAUDE.md
  skills/<name>/                 ──▶ ~/.agents/skills/<name>, ~/.claude/skills/<name>
  hooks/verify-gate.py           ──▶ ~/.agents/hooks/verify-gate.py
  policies/codex/shared.rules    ──▶ ~/.codex/rules/shared.rules
  settings/claude/statusline-command.sh ──▶ ~/.claude/statusline-command.sh
  settings/ (status lines, hooks) ─▶ merged into ~/.claude/settings.json,
                                     ~/.codex/config.toml, ~/.codex/hooks.json
```

- **Most files are linked, not copied.** The installer creates symlinks from the
  agents' folders back to this checkout. An edit here is visible to both agents
  right away.
- **Settings files are merged, not replaced.** For `settings.json`,
  `config.toml`, and `hooks.json`, the installer changes only the keys it manages
  and keeps everything else you have set. It **does replace** your status-line
  setting in each agent (Claude Code's `statusLine`, Codex's `tui.status_line`
  and `tui.status_line_use_colors`) and keeps no copy of the old value, so back
  those up first if you customized them.
- **Existing files and skills are not overwritten.** If a file, folder, or skill
  already exists where the installer wants to create a link, it stops and tells
  you, rather than replacing it. If an install fails partway, it rolls back its
  changes.
- **It is safe to rerun.** Running `make install` again just brings everything up
  to date.

The full list of installed paths is in the
[installation reference](docs/installation.md#installed-paths).

## Installation

### 1. Install the requirements

You need **GNU/Linux** with Bash 4 or newer and GNU coreutils. macOS is not
supported yet. On Debian or Ubuntu:

```bash
sudo apt-get update
sudo apt-get install bash coreutils git make jq python3 python3-tomlkit python3-yaml
```

On other distributions, install the equivalent packages, including the Python
modules `tomlkit` and PyYAML. Install Codex and/or Claude Code separately if you
have not already. The installer sets up both agents either way.

### 2. Clone and install

```bash
git clone https://github.com/chrysogonus/power-agents.git ~/power-agents
cd ~/power-agents
make install
```

The checkout can live anywhere you like. When it finishes, the installer prints
`Done.`

> **Keep the checkout where it is.** The installed files link back to it, so
> moving or deleting the folder breaks your agents' setup.

If the installer reports a conflict with an existing file, see
[Resolving an installation conflict](docs/installation.md#resolving-an-installation-conflict).

### 3. Restart your agents

Close any open Codex or Claude Code sessions and start new ones so they load the
new instructions and skills. **Codex users:** in a new session, run `/hooks` and
approve the verify-gate hooks. Codex ignores new hooks until you do.

### 4. Try a skill

Ask for a skill by name, or just describe the task and let the agent choose one:

| Agent | Example prompt |
| --- | --- |
| Codex | `$ponytail fix this bug using the smallest suitable change` |
| Claude Code | `/ponytail fix this bug using the smallest suitable change` |

To check that a skill is linked to your checkout:

```bash
readlink ~/.agents/skills/ponytail   # should end in /power-agents/skills/ponytail
```

## Making It Your Own

Always edit files **in this repository**, never the installed copies. Then run
`make install`, and restart your agent sessions.

| To change… | Edit… |
| --- | --- |
| Your coding preferences for all projects | [`instructions/general-global.md`](instructions/general-global.md) |
| A skill, or add a new one | `skills/<name>/SKILL.md` ([skill format](skills/README.md#skill-format)) |
| The self-check and cross-review behavior | [`hooks/verify-gate.py`](hooks/verify-gate.py) ([guide](docs/verify-gate.md)) |
| Codex command rules | [`policies/codex/shared.rules`](policies/codex/shared.rules) |
| Codex status line | [`settings/codex/tui.toml`](settings/codex/tui.toml) |
| Claude Code status line | [`settings/claude/statusline-command.sh`](settings/claude/statusline-command.sh) |

Before you commit, run `make check` to make sure nothing is broken.

## Turning Cross-Review On or Off

Cross-review is **off** by default. When it is on, your session and its changes
are sent to the other agent's vendor for a second opinion: Claude Code work goes
to Codex (OpenAI), and Codex work goes to Claude Code (Anthropic). This costs an
extra model run per qualifying turn.

```bash
python3 ~/.agents/hooks/verify-gate.py cross-review on    # or: off, status
```

To turn off the whole self-check for a session, start the agent with
`VERIFY_GATE=0`. See the [verify gate guide](docs/verify-gate.md) for all
options.

## Commands

Run these from your checkout. `make` on its own lists them.

| Command | What it does |
| --- | --- |
| `make install` | Install or update the setup for both agents. |
| `make sync` | Safely pull signed updates and reinstall. Needs a [one-time setup](docs/installation.md#syncing). |
| `make check` | Run all checks and tests on your working copy. |
| `make test` | Run only the behavioral tests. |
| `make ci` | Run the same checks as GitHub Actions. |
| `make eval` | Measure how well skills are chosen and followed. **Uses paid API calls.** [Details](docs/development.md#behavioral-skill-evaluations) |
| `make coding-eval` | Plan coding-outcome trials; running them is paid and needs `--execute`. [Details](docs/development.md#coding-outcome-evaluations) |

## Quality Checks

`make check` and `make ci` additionally need GnuPG and ShellCheck. On Debian or
Ubuntu:

```bash
sudo apt-get install make gnupg jq python3 python3-tomlkit python3-yaml shellcheck
```

Use `make check` while you work and `make ci` before you push. What the checks
cover is described in the [development guide](docs/development.md#quality-checks).

## Repository Layout

```text
power-agents/
├── instructions/   Coding preferences installed for both agents
├── skills/         One folder per skill, each with a SKILL.md
├── hooks/          The verify gate (self-check and cross-review)
├── settings/       Agent-specific settings: status lines and hook entries
├── policies/       Codex command approval rules
├── install.sh      The installer (run through `make install`)
├── sync.sh         Signature-checked updater (run through `make sync`)
├── scripts/        Checks, settings merging, and evaluation runners
├── tests/          Isolated tests that never touch your real setup
├── evals/          Tasks for the coding-outcome evaluations
├── docs/           Detailed reference documentation
└── research/       Notes on upstream skills that were considered
```

`AGENTS.md` at the root holds the instructions for agents working on *this*
repository; it is not installed globally.

## Further Reading

- [Installation reference](docs/installation.md): every installed path, merge
  rules, conflicts, signed sync, and manual uninstall
- [Verify gate and cross-review](docs/verify-gate.md): when it runs, controls,
  cost, and privacy
- [Skills](skills/README.md): the full inventory and how to write a skill
- [Development and evaluations](docs/development.md): checks, adding skills,
  and paid evaluations
- [Contributing](CONTRIBUTING.md), [Security Policy](SECURITY.md), and
  [Code of Conduct](CODE_OF_CONDUCT.md)

## License

Original repository content is available under the [MIT License](LICENSE).
Third-party components keep their own terms and attribution; see
[Third-Party Notices](THIRD_PARTY_NOTICES.md).
