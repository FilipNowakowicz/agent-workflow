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

Because it's a snapshot, the carried-over skills and scripts still contain
`nixos-config`-specific references (e.g. `scripts/validate.sh`,
`nix-verification-loop`, `lib/invariants.nix`). Genericizing those — splitting
"engine" from "consumer-local config" — is the first v2 work item.

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
