# agent-workflow

A self-hosted, evidence-gated **agentic development control plane**: skills,
orchestration, control-plane scripts, schemas, and a learning loop for driving
coding agents from high-level goals to reviewed PRs — with autonomy *earned from
telemetry* and *bounded by deterministic policy*.

The full vision and roadmap live in [`PLAN.md`](PLAN.md); the endgame analysis
and the provider/consumer extraction reasoning live in
[`docs/endgame-analysis.md`](docs/endgame-analysis.md).

## Status: v2 development space (seeded snapshot)

This repo was seeded from the working agent loop in the personal `nixos-config`
flake (the `gcp-agent` issue-loop). The strategy is **fork-forward**, not
migration:

- The `nixos-config` repo keeps running its loop off its own local copies,
  **untouched**, as v1.
- This repo is where **v2 is built** — free to refactor toward the PLAN.md
  control plane without risking the live infra.
- **Later**, `nixos-config` consumes this repo as a flake input (see
  [`flake.nix`](flake.nix)) and deletes its local copies at that point.

**v2 engine decoupling is complete.** All 18 control-plane + orchestration
scripts and the 5 portable skills are repo-agnostic and pass `--self-test`
standalone; generic policy defaults (`governance.yaml`, `model-routing.yaml`,
`capability-profiles.yaml`) ship at the engine root; consumer-local config is
isolated behind `scripts/lib/agent-env.sh` (`AGENT_VERIFY_CMD`, `AGENT_*` paths)
and the `--policy`/`--routing`/`--profiles` flags. See
[`docs/v2-engine-boundary.md`](docs/v2-engine-boundary.md) for the per-script
migration record. The remaining nixos strings live only in self-test fixture
data and the `learning/candidates/` seed corpus.

## Consuming as a flake input

A consumer repo pins this engine and renders its trees into the `.agents/`
convention:

```nix
# flake.nix (consumer)
inputs.agent-workflow.url = "github:FilipNowakowicz/agent-workflow";
# then, e.g. in a derivation/home-manager activation that builds .agents/:
#   ${inputs.agent-workflow.paths.controlPlane} -> .agents/scripts
#   ${inputs.agent-workflow.paths.skills}       -> .agents/skills
#   ${inputs.agent-workflow.paths.learning}     -> .agents/learning
#   ${inputs.agent-workflow.paths.repoMap}      -> .agents/repo-map
#   ${inputs.agent-workflow.paths.schemas}      -> .agents/schemas
#   ${inputs.agent-workflow.paths.orchestration}/* -> scripts/agent-*.sh
```

The consumer supplies its own `agent.config.sh` (see
[`agent.config.example.sh`](agent.config.example.sh)) setting `AGENT_VERIFY_CMD`
and any path overrides, plus its own `governance.yaml` / `model-routing.yaml` /
`capability-profiles.yaml` if it wants repo-specific risk classes. Wiring
`nixos-config` to consume this (and deleting its local copies) is the deferred
fork-forward capstone — tracked separately, not part of this engine work.

## Layout

| Path             | What it is                                                            | Maps back to (consumer)        |
| ---------------- | -------------------------------------------------------------------- | ------------------------------ |
| `skills/`        | Portable workflow skills (issue-driven-dev, issue-tdd, learning…)     | `.agents/skills/`              |
| `orchestration/` | Session + issue-runner + PR-review entrypoints (`agent-*.sh`)         | repo-root `scripts/agent-*.sh` |
| `scripts/`       | Control-plane: dispatch, route, policy-eval, outcome recording, etc. | `.agents/scripts/`             |
| `schemas/`       | Outcome + reviewer-evidence JSON schemas                             | `.agents/schemas/`             |
| `learning/`      | Learning-candidate capture/review/promotion tooling + examples       | `.agents/learning/`            |
| `repo-map/`      | Repo-intelligence index/query helpers                               | `.agents/repo-map/`            |
| `state/`         | Runtime telemetry (gitignored; structure only)                      | `.agents/state/`               |

Nix-specific skills (`nix-verification-loop`, `nix-review-ledger-batch`)
deliberately stay in `nixos-config` — they're welded to that repo's
`validate.sh` and conventions, not part of the generic engine.

## How much of PLAN.md already exists

The `scripts/` control plane already implements a large slice of the roadmap:
issue readiness (`agent-issue-readiness`), routing (`agent-route`),
policy evaluation (`agent-policy-eval`), reviewer-evidence checking
(`agent-review-evidence-check`), outcome recording + stats
(`agent-record-outcome`, `agent-outcome-*`), dispatch (`agent-dispatch`),
liveness (`agent-liveness-gate`), and the weekly digest
(`agent-weekly-digest`). v2 is about hardening and connecting these, not
starting from zero.

## Learning candidates

`learning/candidates/` carries the **active** queue from `nixos-config` as
representative pipeline data (the `archive/` of historical nix-specific lessons
was intentionally left behind). Treat these as example inputs while developing
the review/promotion tooling, not as this repo's own lessons.
