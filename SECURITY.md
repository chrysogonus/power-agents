# Security Policy

## Scope

This repository is the canonical source for personal coding-agent
configuration. Installing it writes symlinks and managed configuration keys into
the invoking user's home directory and the configured Codex and Claude roots
(`CODEX_HOME` and `CLAUDE_CONFIG_DIR`, which may point elsewhere), so the
security-relevant surface is the code and policy that runs or is consumed on
that machine:

- `install.sh`, `sync.sh`, and the `Makefile`
- `scripts/` and `tests/`
- `.github/workflows/`, which runs the checks in CI
- `settings/claude/statusline-command.sh`
- `hooks/verify-gate.py`, which both agents run as a hook on every prompt and
  stop
- `policies/codex/shared.rules`
- `settings/`, `instructions/`, and `skills/` content that agents load
  automatically

See the [installed-paths table](docs/installation.md#installed-paths) to audit exactly what
the installer creates before running it.

## Supported Versions

Only the current `main` branch is supported. There are no releases, tags, or
backported fixes; the fix for any accepted report lands on `main`.

## Reporting a Vulnerability

Report privately through GitHub, not in a public issue:

1. Open the repository's **Security** tab.
2. Choose **Report a vulnerability**.
3. Include the affected file or command, the impact, and the steps needed to
   reproduce it.

Reports are acknowledged on a best-effort basis, typically within seven days.
Please do not open a public issue, pull request, or discussion for a suspected
vulnerability until a fix is available.

## Trust Model

`sync.sh` fast-forwards to the current branch's configured upstream and reruns
the installer. It does not verify commit signatures, so write access to the
upstream repository is what controls the code sync installs. Divergent history
is rejected without moving `HEAD`, and sync refuses tracked or staged local
changes. If installation fails after a fast-forward, sync restores the previous
commit and reruns its installer so symlinked and copied configuration return to
the prior version. See [Syncing](docs/installation.md#syncing).

The installer refuses to replace a same-name skill, a real file, or an incorrect
symlink. It canonicalizes configuration roots before rejecting `/` or duplicate
locations, preserves unmanaged values when reconciling the configured Claude
and Codex settings files, and rolls back an installation if activation fails.

Codex records hook trust against the hook *definition* in `hooks.json`, not the
contents of the script it runs. After the first `/hooks` approval, changes to
`hooks/verify-gate.py` reach Codex through the installed symlink, for example
via `make sync`, without another Codex review. Claude Code likewise runs the
current script contents. Write access to the upstream repository is therefore
the control for this script: anyone who can push there can change the code both
agents run as hooks. With cross-review enabled, the script also sends session
transcripts and diffs to the other agent's vendor; redaction is best-effort.

## Out of Scope

- Application-managed state this repository does not control, including
  Codex's interactive rules, caches, plugins, and bundled skills.
- Risks inherent to running a coding agent with tool access, including agent
  behavior, model output, and prompt injection through content an agent reads.
- Third-party components listed in
  [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md); report those upstream.
- Findings that require an attacker who already has write access to the
  machine, the home directory, or the upstream repository.
