# v2: engine vs. consumer-local config boundary

The v1 snapshot worked, but the engine is welded to the `nixos-config` repo:
~150 hardcoded `.agents/` paths, plus `scripts/validate.sh` / `nix flake check`
baked into scripts and skills. v2's job is to split the **engine** (generic,
reusable, lives here) from **consumer-local config** (per-repo: how to validate,
where state lives, risk policy — PLAN.md §22).

## The seam

The engine already parameterizes via `AGENT_*` env vars, but each script
defaulted those to `.agents/...` independently. v2 centralizes resolution in one
sourced library:

- **`scripts/lib/agent-env.sh`** — source it (don't execute) from any engine
  script. It resolves:
  - `AGENT_ENGINE_DIR` — where the engine lives, derived from the lib's own
    `BASH_SOURCE` location. This is the key decoupling: a script finds its
    siblings relative to itself, so the engine no longer assumes a `.agents/`
    checkout and runs both standalone (this repo) and rendered into a consumer's
    `.agents/scripts/`.
  - `AGENT_REPO_DIR` — the consumer repo (git toplevel / `$PWD`).
  - `AGENT_STATE_DIR`, `AGENT_OUTCOME_DIR`, `AGENT_SESSIONS_DIR`,
    `AGENT_CANDIDATES_DIR` — consumer-relative data paths, defaulting to the
    `.agents/` convention.
  - `AGENT_VERIFY_CMD` — how the consumer validates a change. **Empty by
    default**; the generic engine cannot know this. Replaces the hardcoded
    `scripts/validate.sh` / `nix flake check` references.

- **`agent.config.example.sh`** — a consumer copies this, sets its knobs
  (notably `AGENT_VERIFY_CMD`), and points the engine at it with `AGENT_CONFIG`.

Defaults stay backward-compatible with the rendered-into-consumer `.agents/`
layout, so a consumer that adopts the convention needs no config file.

## Migration status

| Script | Status |
| --- | --- |
| `agent-record-outcome` | **migrated** — reference implementation; self-test green |
| `agent-dispatch` | pending (already collects many `AGENT_*` vars; source the lib) |
| `agent-policy-eval` | pending (`.agents/governance.yaml`, protected-path lists) |
| `agent-route`, `agent-issue-readiness`, `agent-liveness-gate`, `agent-merge-gate`, `agent-review-*`, `agent-outcome-*`, `agent-weekly-digest` | pending |
| `orchestration/*` (`agent-run-issue`, `agent-session`, `agent-review-pr`) | pending — heaviest `validate.sh` / `.agents/` coupling; route through `AGENT_VERIFY_CMD` |
| portable `skills/*` | pending — genericize prose references (`nix-verification-loop`, `lib/invariants.nix`) |

Each migration is its own small PR: source the lib, replace hardcoded paths with
the `AGENT_*` vars, keep the script's embedded self-test green.

## Why this first

Every later v2 capability (dispatcher hardening, real flake outputs, a second
consumer repo) depends on the engine not being hardcoded to one repo. This is
the unblocking step, and it's provable today via the existing self-tests rather
than requiring a live run.
