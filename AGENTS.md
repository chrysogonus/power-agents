# Project Instructions

This repository's core is the verify gate (`hooks/verify-gate.py`), installed
for Codex and Claude Code. Instructions, skills, status lines, Codex rules,
Claude Code guards, permission rules, notifications, session context,
formatting, and subagents are optional components selected with
`./install.sh --components`. Optional hook logic goes in `hooks/agent-hub.py`
(Python standard library only).

- Keep a gate-only install working: it must not need `tomlkit`, PyYAML, or
  Node.js, and must not create or change files that belong to optional
  components.
- Edit files in this repository, not their installed copies under `~/.agents`
  or the configured Codex and Claude roots.
- Keep cross-project instructions in `instructions/general-global.md`.
- Put each skill in `skills/<name>/SKILL.md`; its frontmatter `name` must match
  the directory name.
- Define each subagent once in `subagents/<role>.md`;
  `scripts/render-subagents.py` writes the Claude Code and Codex versions.
- Keep authored Codex rules in `policies/codex/shared.rules`; interactive rules
  remain in the application-managed Codex root.
- Keep agent-specific settings under `settings/<agent>/`.
- Run `./install.sh` after configuration changes. It must remain idempotent and
  preserve supported unmanaged values as documented in `docs/installation.md`.
- Run `./scripts/check.sh` before finishing changes. It includes Bash syntax and
  static analysis for every shell script, isolated behavioral tests, and
  `git diff --check` coverage.
