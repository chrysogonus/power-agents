# Power Agents

**Codex and Claude Code check their own work, and each other's, before they
hand it to you.**

Power Agents installs one hook, the **verify gate**, for both agents. At the end
of a substantial turn it sends the agent back to verify its answer, and it can
have the *other* agent review the work. Run `make install` and both agents get
it.

Everything else in this repository is optional: shared instructions, skills,
status lines, and Codex command rules. [Add them when you want
them](#optional-components).

## Agents That Check Their Work

Coding agents often stop as soon as an answer *sounds* right. They report a fix
without re-running the tests, or describe code they never re-read. Power Agents
installs a hook, the **verify gate**, that changes what happens at the end of a
turn:

```text
 you ask ──▶ agent works ──▶ agent tries to finish
                                     │
          changed files, or gave a long answer that isn't a question?
                  │ no                           │ yes
                  ▼                              ▼
                done        1. Self-check: the agent is sent back to verify
                               its answer against files, tests, or docs, and
                               to fix what is wrong
                                                 ▼
                            2. Cross-review (optional): the other agent
                               reviews the work; the first agent is asked to
                               accept or reject each point and fix what it
                               accepts
                                                 ▼
                                               done
```

**1. Self-check (on by default).** Before the agent may stop, it is sent back
once with a fixed checklist:

- Verify each claim, code change, and command against something it can check
  now: re-read the changed files, run the tests or linters, re-check the docs.
  Earlier reasoning doesn't count.
- Look for gaps: edge cases, callers, configs or tests not updated, unstated
  assumptions, security impact.
- Fix real problems, and keep what holds. Being asked to look again is not a
  reason to change anything.

It is asked to end with a short note listing what it checked and how, what it
fixed, and what it could not verify. In Claude Code you see the first answer,
then this note and any corrections. The gate then ends the turn with a
one-line summary, such as `verify gate · self-check fixed, edited files ·
cross-review (Codex): accepted 2, rejected 1`.

**2. Cross-review (off by default).** Claude Code's work is reviewed by Codex,
and Codex's work by Claude Code. The reviewer gets the session transcript and
the `git diff`, is told not to change anything, and reports bugs, security
issues, missed requirements, and claims the evidence doesn't support. The
original agent is then asked to say which points it accepts or rejects and why,
and to fix what it accepts. Models from different vendors tend to miss different
things. [How the reviewer is restricted →](docs/verify-gate.md#how-the-reviewer-is-restricted)

**What this means for you:**

- **A push toward evidence.** The agent is asked to back its claims about code,
  commands, and test results with checks it runs now, not with what it
  remembers.
- **A second look at every substantial turn.** Wrong statements, forgotten
  files, and overpromises get another chance to be caught before you act on
  them.
- **You can see what was checked.** Each check is asked to say what was
  verified and what wasn't, so you know which parts to double-check yourself.
- **It stays out of the way.** Turns that change no files skip the gate when the
  answer is short or ends with a question to you. There are at most two extra
  passes per turn. A reviewer that is missing, fails, or times out is skipped
  with a notice and never blocks you.

**What it can't do:** the gate is a prompt, not a guarantee. It sends the
checklist and lets the turn finish afterward. It cannot confirm that the agent
actually ran the checks, and the agent can still be wrong after them. Review
important changes yourself.

**The trade-offs:** each qualifying turn takes longer and costs an extra model
pass, and cross-review adds a full review by the other agent. Cross-review also
sends your transcript and diff to the *other* vendor, so leave it off for work
that must stay with one vendor.

**Measured so far (October 2026, one user, Claude Code only, 20 sessions over
two days):** 94 turns were self-checked, and in 41 of them (44%) the agent
reported fixing something. Of 43 cross-reviews by Codex, 23 (53%) reported
issues. These numbers count how often the gate led to a change, not whether
the final answers were better. To measure that, run the randomized
[experiment or the gate-on/off benchmark](docs/experiment.md). Run
`python3 ~/.agents/hooks/verify-gate.py stats` to see your own numbers.

[Controls, cost, and privacy details →](docs/verify-gate.md)

## Optional Components

`make install` installs only the verify gate. These components are off unless
you select them:

| Component | What it means for you |
| --- | --- |
| `instructions` | Both agents follow the same personal coding preferences in every project ([`instructions/general-global.md`](instructions/general-global.md)). |
| `skills` | 13 ready-made guides for specific jobs, such as minimal bug fixes, code reviews, React, Postgres, security, and UI design. [Browse the skills →](skills/README.md) |
| `statusline` | Both agents show the project, model, context used, and usage limits at the bottom of the terminal. |
| `codex-rules` | Codex asks before running some test commands (`pytest` from a virtual environment, `python -m pytest`). |

Choose them with a comma-separated list, or `all` or `none`:

```bash
./install.sh --components skills,instructions
./install.sh --components all
```

The installer saves your choice in `~/.config/power-agents/components`, for the
agent folders it installed into, so a later `make install` or `make sync` keeps
it. Leaving a component out of a new
list removes what the installer added for it, and nothing else. If you installed
before components existed, your next install keeps everything already installed.
[Details →](docs/installation.md#choosing-components)

Power Agents does **not** install Codex or Claude Code themselves, and does not
set up their accounts.

## How It Works

```text
  this repository                       your home directory
  ───────────────                       ───────────────────
  Always installed
  hooks/verify-gate.py           ──▶ ~/.agents/hooks/verify-gate.py
  settings/*/hooks.json          ──▶ merged into ~/.claude/settings.json,
                                     ~/.codex/hooks.json

  Optional components
  instructions/general-global.md ──▶ ~/.codex/AGENTS.md, ~/.claude/CLAUDE.md
  skills/<name>/                 ──▶ ~/.agents/skills/<name>, ~/.claude/skills/<name>
  settings/ (status lines)       ──▶ ~/.claude/statusline-command.sh, merged into
                                     ~/.claude/settings.json, ~/.codex/config.toml
  policies/codex/shared.rules    ──▶ ~/.codex/rules/shared.rules
```

- **Most files are linked, not copied.** The installer creates symlinks from the
  agents' folders back to this checkout. An edit here is visible to both agents
  right away.
- **Settings files are merged, not replaced.** For `settings.json`,
  `config.toml`, and `hooks.json`, the installer changes only the keys it manages
  and keeps everything else you have set. With the `statusline` component, it
  **does replace** your status-line setting in each agent (Claude Code's
  `statusLine`, Codex's `tui.status_line` and `tui.status_line_use_colors`) and
  keeps no copy of the old value, so back those up first if you customized them.
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
sudo apt-get install bash coreutils git make jq python3
```

The optional components need two more Python modules: `statusline` needs
`tomlkit` (`python3-tomlkit`) and `skills` needs PyYAML (`python3-yaml`). On
other distributions, install the equivalent packages. Install Codex and/or
Claude Code separately if you have not already. The installer sets up both
agents either way.

### 2. Clone and install

```bash
git clone https://github.com/chrysogonus/power-agents.git ~/power-agents
cd ~/power-agents
make install
```

This installs the verify gate. To add [optional
components](#optional-components), run `./install.sh --components LIST` instead.
The checkout can live anywhere you like. When it finishes, the installer prints
`Done.` and lists what it installed.

> **Keep the checkout where it is.** The installed files link back to it, so
> moving or deleting the folder breaks your agents' setup.

If the installer reports a conflict with an existing file, see
[Resolving an installation conflict](docs/installation.md#resolving-an-installation-conflict).

### 3. Restart your agents

Close any open Codex or Claude Code sessions and start new ones so they load the
new configuration. **Codex users:** in a new session, run `/hooks` and approve
the verify-gate hooks. Codex ignores new hooks until you do.

### 4. Try it

Ask either agent to change a file. When it tries to finish, the verify gate
sends it back once to check its work, and you see a short note on what it
checked. To also get a review from the other agent, [turn on
cross-review](#turning-cross-review-on-or-off).

With the `skills` component, ask for a skill by name, or just describe the task
and let the agent choose one:

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
| The self-check and cross-review behavior | [`hooks/verify-gate.py`](hooks/verify-gate.py) ([guide](docs/verify-gate.md)) |
| Gate settings or a check command for one repository | `~/.config/power-agents/projects.json` ([format](docs/verify-gate.md#per-project-settings)) |
| Which optional components are installed | Run `./install.sh --components LIST` |
| Your coding preferences for all projects | [`instructions/general-global.md`](instructions/general-global.md) |
| A skill, or add a new one | `skills/<name>/SKILL.md` ([skill format](skills/README.md#skill-format)) |
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

To set cross-review, or a check command the gate runs for you, for one
repository only, use [per-project
settings](docs/verify-gate.md#per-project-settings).

To turn off the whole self-check for a session, start the agent with
`VERIFY_GATE=0`. See the [verify gate guide](docs/verify-gate.md) for all
options.

## Commands

Run these from your checkout. `make` on its own lists them.

| Command | What it does |
| --- | --- |
| `make install` | Install or update the verify gate and your saved optional components for both agents. |
| `make sync` | Pull upstream updates and reinstall. [Details](docs/installation.md#syncing) |
| `make check` | Run all checks and tests on your working copy. |
| `make test` | Run only the behavioral tests. |
| `make ci` | Run the same checks as GitHub Actions. |
| `make eval` | Measure how well skills are chosen and followed. **Uses paid API calls.** [Details](docs/development.md#behavioral-skill-evaluations) |
| `make coding-eval` | Plan coding-outcome trials; running them is paid and needs `--execute`. [Details](docs/development.md#coding-outcome-evaluations) |

## Quality Checks

`make check` and `make ci` additionally need ShellCheck. On Debian or Ubuntu:

```bash
sudo apt-get install make jq python3 python3-tomlkit python3-yaml shellcheck
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
├── sync.sh         Fast-forward updater (run through `make sync`)
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
  rules, conflicts, sync, and uninstall
- [Verify gate and cross-review](docs/verify-gate.md): when it runs, controls,
  cost, and privacy
- [Measuring the verify gate](docs/experiment.md): the randomized experiment,
  blinded audits, export, and the controlled benchmark
- [Skills](skills/README.md): the full inventory and how to write a skill
- [Development and evaluations](docs/development.md): checks, adding skills,
  and paid evaluations
- [Contributing](CONTRIBUTING.md), [Security Policy](SECURITY.md), and
  [Code of Conduct](CODE_OF_CONDUCT.md)

## License

Original repository content is available under the [MIT License](LICENSE).
Third-party components keep their own terms and attribution; see
[Third-Party Notices](THIRD_PARTY_NOTICES.md).
