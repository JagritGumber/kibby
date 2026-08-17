# Architecture

Kibby has four ownership boundaries:

1. The distribution package manager owns native packages.
2. The user's existing Hyprland configuration remains host-owned.
3. The user owns source copied into live XDG configuration paths.
4. Kibby owns marked integration lines, pristine baselines, transaction backups,
   and the lockfile.

The Rust CLI is split into a library and a thin command wrapper. `kibby-core`
detects adapters, resolves capabilities, creates deterministic plans, performs
atomic writes, validates the result, and rolls back failures. `kibby-cli` handles
arguments, presentation, and confirmation.

Foundation is not a visible shell and does not depend on Quickshell. Optional QML
components depend on the separate `quickshell-runtime` package. Component
manifests are declarative and cannot contain root hooks or arbitrary installer
commands.

Every mutation follows one transaction:

1. Detect configuration and capabilities.
2. Produce a complete plan.
3. Obtain explicit approval.
4. Install approved official packages, if any.
5. Back up every host-owned file that will change.
6. Atomically write Kibby-owned source and one marked host include.
7. Reload and validate Hyprland when a live session is available.
8. Commit the lockfile only after validation.
9. Roll back file changes if validation fails.
