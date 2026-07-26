# agent-workflow

A self-hosted, evidence-gated **agentic development control plane**: skills,
orchestration, control-plane scripts, schemas, and a learning loop for driving
coding agents from high-level goals to reviewed PRs — with autonomy *earned from
telemetry* and *bounded by deterministic policy*.

Design principles and working conventions for agents in this repo live in
[`CLAUDE.md`](CLAUDE.md); deferred/future work lives in
[`docs/backlog.md`](docs/backlog.md). The endgame analysis and the
provider/consumer extraction reasoning live in
[`docs/endgame-analysis.md`](docs/endgame-analysis.md). The provider-vs-
installed filesystem contract is documented in
[`docs/provider-consumer-layout.md`](docs/provider-consumer-layout.md). CI and
the local-equivalent commands are documented in [`docs/ci.md`](docs/ci.md).
The self-hosted issue loop's architecture, prerequisites, trust boundary, and
failure modes are documented in
[`docs/gcp-issue-loop.md`](docs/gcp-issue-loop.md).

Public-use basics are tracked in [`LICENSE`](LICENSE), [`SECURITY.md`](SECURITY.md),
[`CONTRIBUTING.md`](CONTRIBUTING.md), and
[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). The repository is still a v2
development space; those files define the intended public contract, not a claim
that the loop is turnkey for arbitrary repositories yet.

## What this gives you

- **Issue-shaped work intake**: skills and readiness checks for turning rough
  goals into scoped GitHub issues with acceptance criteria and validation.
- **A self-hosted issue loop**: orchestration scripts for running one issue per
  agent session, collecting structured outcomes, and recovering useful PRs.
- **Evidence-gated review**: reviewer-evidence schemas and checks that bind a
  recommendation to issue criteria, validation commands, and residual risk.
- **Deterministic policy hooks**: routing, policy evaluation, liveness checks,
  merge gates, and outcome dashboards that keep authority out of model prose.
- **A learning pipeline**: candidate capture/review/promotion tooling for
  turning repeated failures into repo-side checks, docs, hooks, or skills.

## What to use first

If you are exploring the repo directly, start with the source trees:

1. Read [`docs/provider-consumer-layout.md`](docs/provider-consumer-layout.md)
   to understand provider paths versus installed `.agents/` paths.
2. Inspect `skills/issue-tdd/SKILL.md` and
   `skills/issue-driven-development/SKILL.md` for the issue-first workflow.
3. Run small local checks such as:

   ```sh
   bash scripts/agent-issue-readiness --self-test
   bash scripts/agent-record-outcome --self-test
   bash learning/scripts/validate-candidates.sh learning
   ```

If you are thinking about consuming this from another repo, pin `flake.nix`'s
`paths` output as a flake input, then run [`install.sh`](install.sh) to render
it into your repo's `.agents/` tree and root `scripts/agent-*.sh`
entrypoints — see [`examples/consumer-flake/`](examples/consumer-flake/) for
the end-to-end flow and
[`docs/provider-consumer-layout.md`](docs/provider-consumer-layout.md) for
the full consumption contract. A NixOS module is not part of this contract
yet.

## Components

- **Skills** (`skills/`): agent-facing workflows for issue design,
  implementation, repo-map lookup, and learning review.
- **Control plane** (`scripts/`): deterministic checks for readiness, routing,
  evidence, outcomes, liveness, dispatch, merge gating, and freeze/quarantine.
- **Orchestration** (`orchestration/`): operator entrypoints for the
  self-hosted GCP-style issue loop and reviewer handoff.
- **Learning** (`learning/`): candidate schema, indexing, liveness checks,
  review helpers, and promotion scaffolding.
- **Schemas** (`schemas/`): JSON contracts for outcome records and reviewer
  evidence.
- **Repo map** (`repo-map/`): lightweight indexing and query helpers for
  finding likely files before broad exploration, plus a co-change lookup for
  blast-radius awareness before editing a file.
- **Canaries** (`canaries/`): adversarial canary definitions and a
  deterministic checker proving refusal, not just deterministic diffs, is
  covered.
- **Personal skills** (`personal-skills/`): general-purpose skills outside
  this repo's agent-workflow domain, kept here for convenience only. Not
  part of the flake's `paths` output or `install.sh` — see
  [`personal-skills/README.md`](personal-skills/README.md).

## Maturity and sharp edges

This is real dogfood from a NixOS/GCP agent loop, extracted into a reusable
provider repo. It is not yet a turnkey product. In particular:

- skills and tooling that reference consumer validation (the equivalent of
  `scripts/validate.sh`) or a Nix-specific verification skill now treat those
  as consumer-local conventions to point at, not hardcoded assumptions;
  `learning/scripts/scaffold-promotion-check.sh` takes `--validate-file` and
  an arbitrary `--validate-target` rather than assuming a fixed script/target
  pair;
- live model calls, GCP hosts, credentials, and downstream validation commands
  remain operator-local concerns;
- learned routing has its stats/annotation machinery built and, as of the
  first real dogfood runs, validated against real outcome telemetry — see
  below. Branch-tournament benchmarks and extracting this into a separate
  agent-loop repo remain deliberately deferred — see
  [`docs/backlog.md`](docs/backlog.md) for the trigger conditions.

## Status: v2 development space (seeded snapshot)

This repo was seeded from the working agent loop in the personal `nixos-config`
flake (the `gcp-agent` issue-loop). The strategy is **fork-forward**, not
migration:

- The `nixos-config` repo keeps running its loop off its own local copies,
  **untouched**, as v1.
- This repo is where **v2 is built** — free to refactor toward the target
  control plane described in [`CLAUDE.md`](CLAUDE.md) without risking the
  live infra.
- **Later**, `nixos-config` consumes this repo as a flake input (see
  [`flake.nix`](flake.nix)) and deletes its local copies at that point.

Because it's a snapshot, the carried-over skills and scripts originally
hardcoded `nixos-config`-specific references (`scripts/validate.sh`,
`nix-verification-loop`, `lib/invariants.nix`) as if they were generic.
Splitting "engine" from "consumer-local config" was the first v2 work item;
skills and tooling now treat those as consumer-local conventions to point at
(configurable, described conditionally) rather than assumptions baked into
the provider surface. `nix-verification-loop` and `lib/invariants.nix`
themselves are still nixos-config-only artifacts and are not part of this
repo (see the note on Nix-specific skills below).

## Layout

This repo is the **provider** layout: the top-level directories are the source
trees exported by the flake. A downstream repo installs those trees under its
own `.agents/` directory, plus root `scripts/agent-*.sh` operator entrypoints.
When docs or skills say `.agents/...`, they are describing that installed
consumer layout. When validating this repo directly, use the provider paths.

| Path             | What it is                                                            | Maps back to (consumer)        |
| ---------------- | -------------------------------------------------------------------- | ------------------------------ |
| `skills/`        | Portable workflow skills (issue-driven-dev, issue-tdd, learning…)     | `.agents/skills/`              |
| `orchestration/` | Session + issue-runner + PR-review entrypoints (`agent-*.sh`)         | repo-root `scripts/agent-*.sh` |
| `scripts/`       | Control-plane: dispatch, route, policy-eval, outcome recording, etc. | `.agents/scripts/`             |
| `schemas/`       | Outcome + reviewer-evidence JSON schemas                             | `.agents/schemas/`             |
| `learning/`      | Learning-candidate capture/review/promotion tooling + examples       | `.agents/learning/`            |
| `repo-map/`      | Repo-intelligence index/query helpers                               | `.agents/repo-map/`            |
| `state/`         | Runtime telemetry (gitignored; structure only)                      | `.agents/state/`               |

Examples:

```sh
# Provider checkout
bash scripts/agent-record-outcome --self-test
bash learning/scripts/validate-candidates.sh learning

# Installed consumer checkout
bash .agents/scripts/agent-record-outcome --self-test
bash .agents/learning/scripts/validate-candidates.sh .agents/learning
```

Nix-specific skills (`nix-verification-loop`, `nix-review-ledger-batch`)
deliberately stay in `nixos-config` — they're welded to that repo's
`validate.sh` and conventions, not part of the generic engine.

## How much is built

The `scripts/` control plane already implements: issue readiness
(`agent-issue-readiness`), routing (`agent-route`), policy evaluation
(`agent-policy-eval`), reviewer-evidence checking
(`agent-review-evidence-check`), outcome recording + stats
(`agent-record-outcome`, `agent-outcome-*`), dispatch (`agent-dispatch`),
liveness (`agent-liveness-gate`), freeze/quarantine (`agent-freeze`), the
weekly digest (`agent-weekly-digest`), and adversarial canaries (`canaries/`,
`agent-canary-check`).

Learned routing has real outcome-stats aggregation (`agent-outcome-stats`)
and advisory annotation of route decisions (`agent-route --outcome-dir`,
surfacing `path_class_stats` in JSON output) already built and self-tested.
Its first run against real accumulated telemetry (33 records from actual
dispatch runs) found and fixed one concrete issue: the `nix-modules` path
class had a 36% failure rate, every instance an inner-session timeout, not a
code-quality problem — fixed by raising the default
`AGENT_INNER_TIMEOUT_SECONDS`. What's still not built is the deeper loop —
policy or dispatch actually changing a decision based on
`path_class_stats` — deliberately deferred; see
[`docs/backlog.md`](docs/backlog.md) for why and what would trigger it.

Branch-tournament benchmarks and extracting a separate agent-loop repo also
remain deliberately not started — see [`docs/backlog.md`](docs/backlog.md).

## Learning candidates

`learning/candidates/` currently has no open candidates: the `nixos-config`-
seeded queue was curated (issue #29) into `learning/candidates/archive/`
(resolved, not-applicable, or superseded items), and the two that were
genuine active backlog for this repo's own control-plane code have since been
implemented and archived as `promoted` (`fix-pr: 42`). One strong capture is
kept at `learning/examples/captured-candidate/` purely as a public example of
the candidate format. See
[`learning/README.md`](learning/README.md#candidate-status-in-this-provider-repo)
for the full breakdown.
