## Summary

<!-- What changes, and why. -->

## Areas touched

<!-- For example: install.sh, skills/<name>, policies/codex/shared.rules. -->

## Checklist

- [ ] `./install.sh` rerun; it is still idempotent and preserved unmanaged
      values in `~/.claude/settings.json` and `~/.codex/config.toml`
- [ ] `make check` passes
- [ ] `make ci` passes
- [ ] Documentation updated (`README.md`, `skills/README.md`) where behavior or
      inventory changed
- [ ] Commits are signed and follow the `type(scope): summary` convention
- [ ] Every changed line traces to the stated purpose
