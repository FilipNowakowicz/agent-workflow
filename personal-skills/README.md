# Personal Skills

General-purpose Claude Code skills that aren't specific to the
agentic-development-workflow domain this repo otherwise covers (issue
readiness, dispatch, review, learning, repo-map). Things like chart/dataviz
helpers, design guidance, or other task skills that don't fit that domain
live here instead.

This directory is deliberately **not** part of the provider/consumer
contract:

- it is not listed in `flake.nix`'s `paths` output, so pinning this repo as
  a flake input never pulls it in;
- `install.sh` never installs it into a consumer's `.agents/` tree.

It exists here purely for convenience (one repo, one clone) and is meant to
be symlinked from `~/.claude/skills` for local use. If this directory grows
enough to be worth sharing or versioning on its own, split it into its own
repo rather than folding it into the exported `skills/` tree above.
