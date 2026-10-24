# Project Instructions

This repository's core is the verify gate (`hooks/verify-gate.py`), installed
for Codex and Claude Code. Instructions, skills, status lines, and Codex rules
are optional components selected with `./install.sh --components`.

- Keep a gate-only install working: it must not need `tomlkit` or PyYAML, and
  must not create or change files that belong to optional components.
- Edit files in this repository, not their installed copies under `~/.agents`
  or the configured Codex and Claude roots.
- Keep cross-project instructions in `instructions/general-global.md`.
- Put each skill in `skills/<name>/SKILL.md`; its frontmatter `name` must match
  the directory name.
- Keep authored Codex rules in `policies/codex/shared.rules`; interactive rules
  remain in the application-managed Codex root.
- Keep agent-specific settings under `settings/<agent>/`.
- Run `./install.sh` after configuration changes. It must remain idempotent and
  preserve supported unmanaged values as documented in `docs/installation.md`.
- Run `./scripts/check.sh` before finishing changes. It includes Bash syntax and
  static analysis for every shell script, isolated behavioral tests, and
  `git diff --check` coverage.
