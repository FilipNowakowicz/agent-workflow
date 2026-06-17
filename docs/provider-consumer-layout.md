# Provider And Installed Layouts

`agent-workflow` has two layouts by design.

## Provider Layout

This repository is the provider. Its top-level directories are the source of
truth for reusable workflow components:

| Provider path     | Purpose                                      |
| ----------------- | -------------------------------------------- |
| `skills/`         | Portable agent skills                        |
| `scripts/`        | Control-plane scripts                        |
| `orchestration/`  | Operator entrypoints for sessions and runs   |
| `schemas/`        | JSON schemas                                 |
| `learning/`       | Learning-candidate tooling and examples      |
| `repo-map/`       | Repo-intelligence helpers                    |
| `state/`          | Runtime-state shape only, not committed data |

Run provider-local checks from this checkout with provider paths, for example:

```sh
bash scripts/agent-record-outcome --self-test
bash learning/scripts/validate-candidates.sh learning
```

## Installed Consumer Layout

A consumer repository installs the workflow under its own `.agents/` tree and
keeps root orchestration entrypoints where operators already run them:

| Provider path     | Installed path in a consumer repo        |
| ----------------- | ---------------------------------------- |
| `skills/`         | `.agents/skills/`                        |
| `scripts/`        | `.agents/scripts/`                       |
| `schemas/`        | `.agents/schemas/`                       |
| `learning/`       | `.agents/learning/`                      |
| `repo-map/`       | `.agents/repo-map/`                      |
| `state/`          | `.agents/state/`                         |
| `orchestration/`  | repo-root `scripts/agent-*.sh` wrappers  |

In consumer docs and skills, commands like
`bash .agents/scripts/agent-issue-readiness --issue 123` are intentional:
they describe the installed layout that an agent sees while working in the
target repository.

## Interpreting Existing Examples

Until the installer contract is finalized, examples follow this rule:

- commands under `scripts/`, `learning/scripts/`, `repo-map/scripts/`, and
  `orchestration/` are provider-local when run in this repo;
- commands under `.agents/...` describe the installed consumer layout;
- references to consumer-specific validation such as `scripts/validate.sh`
  are examples from the original dogfood repo and should become configurable
  before public reuse.

## Consumption Contract

The public contract for consuming this repo (issue #30) is flake paths
**plus** an installer script, not a NixOS module or a built package:

- `flake.nix`'s `paths` output exposes each provider source tree as a plain
  Nix path. It is read-only and reproducible (pin a rev in `flake.lock`),
  but it does not materialize files into a consumer repo's working tree —
  that would require either a build step that writes outside the Nix store,
  or a NixOS module wiring activation-time file management, both bigger
  than this repo's current maturity warrants.
- `install.sh` at this repo's root is the actual install step: given
  `--source` (a checkout or `nix flake prefetch`-resolved store path of this
  repo) and `--target` (the consumer repo root), it copies the source trees
  into `.agents/` and the orchestration entrypoints into root-level
  `scripts/agent-*.sh`, matching the table above. It is idempotent and
  refuses to clobber an existing install without `--force`.
- `check-flake-outputs.sh` is a local smoke test, independent of any
  consumer, proving the flake's `paths` output resolves to real, non-empty
  directories with expected marker files before anyone pins it.
- `examples/consumer-flake/` shows the end-to-end flow: pinning the input in
  a consumer `flake.nix`, then running `install.sh` against a
  `nix flake prefetch`-resolved path.

A NixOS dispatcher module is explicitly out of scope here — see issue #30's
non-goals; it may fall out naturally once a real consumer needs activation-
time install rather than an explicit, operator-run script.

## Provider-local Policy Metadata

`governance.yaml`, `model-routing.yaml`, and `capability-profiles.yaml` live
at this repo's root and describe **this provider repo's own** path classes
(`scripts/`, `orchestration/`, `skills/`, `learning/`, `repo-map/`,
`schemas/`, `docs/`, and public-release files like `LICENSE`). They are
consumed by `scripts/agent-route`, `scripts/agent-policy-eval`, and
`scripts/agent-routing-check` when run from this checkout, and validated by
those scripts' `--self-test` modes.

A consumer repo that installs this control plane under `.agents/` should
copy and adapt these three files to its own `.agents/governance.yaml`,
`.agents/model-routing.yaml`, and `.agents/capability-profiles.yaml`,
rewriting the path-class patterns for its own repo layout (e.g. NixOS
host/module trees) rather than reusing these provider-shaped patterns
verbatim.
