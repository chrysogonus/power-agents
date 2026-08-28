# Security Policy

## Scope

This repository is the canonical source for personal coding-agent
configuration. Installing it writes symlinks and managed configuration keys into
the invoking user's home directory, so the security-relevant surface is the code
and policy that runs or is consumed on that machine:

- `install.sh` and `sync.sh`
- `scripts/` and `tests/`
- `settings/claude/statusline-command.sh`
- `policies/codex/shared.rules`
- `settings/` and `instructions/` content that agents load automatically

See the installed-paths table in [`README.md`](README.md) to audit exactly what
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

`sync.sh` verifies incoming history before it changes the working tree or runs
any incoming code. Every commit in the incoming range must carry a valid
OpenPGP signature whose primary-key fingerprint appears in an allowlist stored
outside this repository at `~/.config/power-agents/trusted-signing-keys`.
Unsigned, invalid, expired, revoked, or unlisted signatures and divergent
history are all rejected without moving `HEAD`. Sync also refuses tracked or
staged local changes. If installation fails after a verified fast-forward, sync
restores the previous commit and reruns its installer so symlinked and copied
configuration return to the prior version. See
[Syncing](README.md#syncing) for setup.

The installer refuses to replace a same-name skill, a real file, or an incorrect
symlink. It canonicalizes configuration roots before rejecting `/` or duplicate
locations, preserves unmanaged values when reconciling the configured Claude
and Codex settings files, and rolls back an installation if activation fails.

## Out of Scope

- Application-managed state this repository does not control, including
  Codex's interactive rules, caches, plugins, and bundled skills.
- Risks inherent to running a coding agent with tool access, including agent
  behavior, model output, and prompt injection through content an agent reads.
- Third-party components listed in
  [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md); report those upstream.
- Findings that require an attacker who already has write access to the
  machine, the home directory, or the signing key.
