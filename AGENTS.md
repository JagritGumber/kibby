# Kibby agent entrypoint

Preserve the user's existing Hyprland configuration; Kibby owns only marked
includes and files below Kibby-owned directories. Read `docs/architecture.md`
and the relevant package manifest before editing.

- Never automate package removal, AUR builds, theme replacement, or arbitrary
  privileged hooks.
- Keep CLI wrappers thin; transaction, validation, and recovery behavior belongs
  in `kibby-core`.
- Test mutating behavior with a temporary HOME before proposing a live canary.
- Keep private migrations, personal journals, session handoffs, and worktree
  state outside the public repository.
