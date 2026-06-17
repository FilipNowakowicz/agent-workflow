# Example: Consuming agent-workflow From Another Repo

This directory is a minimal example flake, not a real consumer repo. It
shows the two halves of the consumption contract (issue #30):

1. `flake.nix` here pins `agent-workflow` as a flake input, the same way
   you'd pin `nixpkgs` — that gets you a tracked, reproducible version in
   your own `flake.lock`.
2. `install.sh` (at this repo's root) is the actual install step: it copies
   agent-workflow's source trees into your repo's `.agents/` directory and
   its orchestration entrypoints into root-level `scripts/agent-*.sh`,
   matching the layout documented in
   [`../../docs/provider-consumer-layout.md`](../../docs/provider-consumer-layout.md).

A flake input alone does not materialize files into your working tree —
`inputs.agent-workflow.paths.*` are Nix store paths, useful for other Nix
code to reference, but not something you want to commit or hand-edit
directly. `install.sh` resolves a concrete path for you and copies from it.

## From a real consumer repo

```sh
# 1. Pin the version (optional, but recommended for a tracked, reproducible
#    install — this is what examples/consumer-flake/flake.nix does):
nix flake lock --update-input agent-workflow   # after adding the input above

# 2. Materialize a concrete checkout of agent-workflow (any flake ref works:
#    a tag, a commit, or — as below — the latest default branch):
src=$(nix flake prefetch github:FilipNowakowicz/agent-workflow --json | jq -r .storePath)

# 3. Install into your repo (run from your repo root; --target defaults to
#    nothing, it must be passed explicitly):
bash "$src/install.sh" --source "$src" --target .
```

Re-running `install.sh` refuses to clobber an existing install unless you
pass `--force` — see `install.sh --help`.

`install.sh` installs `governance.yaml`, `model-routing.yaml`, and
`capability-profiles.yaml` as `.agents/*.yaml.example`, not as live files:
their path-class patterns are shaped for agent-workflow's own provider
layout and need to be rewritten for your repo's actual layout before you
rename away the `.example` suffix and opt into policy gating.

## Local validation

This repo's own `check-flake-outputs.sh` proves agent-workflow's `paths`
output resolves to real, non-empty directories before you ever pin it:

```sh
bash ../../check-flake-outputs.sh
```
