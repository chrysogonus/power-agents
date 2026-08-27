# Contributing

This repository is the canonical home for shared Codex and Claude Code
configuration. Read [`AGENTS.md`](AGENTS.md) and [`CLAUDE.md`](CLAUDE.md) first;
they carry the authoritative project rules, and this document only summarizes
the workflow around them.

## Ground Rules

Edit files in this repository, never their installed copies under `~/.agents`,
`~/.codex`, or `~/.claude`. Those paths are symlinks or reconciled
configuration, and edits made there are lost or cause the installer to refuse
to run.

Keep content where it belongs:

- Cross-project instructions in `instructions/general-global.md`
- One skill per `skills/<name>/SKILL.md`, with frontmatter `name` matching the
  directory name
- Authored Codex rules in `policies/codex/shared.rules`; rules created through
  Codex approval prompts stay in the application-managed
  `~/.codex/rules/default.rules`
- Agent-specific settings under `settings/<agent>/`

## Workflow

1. Make the change in this repository.
2. Run `./install.sh`. It must stay idempotent and must preserve unmanaged
   values in `~/.claude/settings.json` and `~/.codex/config.toml`.
3. Run `make check` while iterating. It parses and statically analyzes every
   shell script, validates skill metadata, exercises the installer under
   isolated temporary home directories, and rejects whitespace errors.
4. Run `make ci` before pushing. It runs the same pipeline as GitHub Actions,
   against both the working tree and a source archive of `HEAD`.

Install the required tooling first; see
[Quality Checks](README.md#quality-checks).

## Commits and Pull Requests

- Use the existing `type(scope): summary` commit style, for example
  `fix(installer): activate Claude Code status line`.
- Sign commits with OpenPGP. `sync.sh` rejects any commit whose signature is
  missing or whose primary-key fingerprint is not allowlisted.
- Update `README.md` or `skills/README.md` when behavior or inventory changes.
- Keep diffs surgical: every changed line should trace to the stated purpose.

## Reporting Problems

Open an issue using one of the forms under
[`.github/ISSUE_TEMPLATE/`](.github/ISSUE_TEMPLATE). For a suspected
vulnerability, follow [`SECURITY.md`](SECURITY.md) instead of filing a public
issue.
