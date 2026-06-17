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

The flake currently exposes source paths only. It does not yet install files
into a consumer repo by itself.

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
