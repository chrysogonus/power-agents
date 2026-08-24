# Project Instructions

This repository is the canonical source for personal configuration shared by
Codex and Claude Code.

- Edit files in this repository, not their installed copies under `~/.agents`,
  `~/.codex`, or `~/.claude`.
- Keep cross-project instructions in `instructions/general-global.md`.
- Put each skill in `skills/<name>/SKILL.md`; its frontmatter `name` must match
  the directory name.
- Keep authored Codex rules in `policies/codex/shared.rules`; interactive rules
  remain in the application-managed `~/.codex/rules/default.rules`.
- Keep agent-specific settings under `settings/<agent>/`.
- Run `./install.sh` after configuration changes. It must remain idempotent and
  preserve unmanaged values in `~/.codex/config.toml`.
- Run `./scripts/check.sh` before finishing changes. It includes Bash syntax and
  static analysis for every shell script, isolated behavioral tests, and
  `git diff --check` coverage.
