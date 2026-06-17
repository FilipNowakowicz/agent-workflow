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
| `agent-outcome-index`, `agent-outcome-stats`, `agent-outcome-dashboard`, `agent-weekly-digest` | **migrated** — `AGENT_OUTCOME_DIR` / `AGENT_CANDIDATES_DIR`; self-tests green |
| `agent-dispatch` | **migrated** — sibling scripts resolve via `AGENT_ENGINE_DIR`; repo-dir default `.` → git toplevel. Fixed a latent bug: its self-test was failing standalone because the recorder default (`.agents/scripts/...`) didn't resolve outside a consumer checkout |
| `agent-policy-eval`, `agent-review-stage` | **unblocked** — seeded a generic engine-default `governance.yaml` at the engine root (the default `<engine>/../governance.yaml` path); both self-tests now pass standalone. No script edit needed: the consumer overrides via its own `governance.yaml` / `--policy`. review-stage was failing only because its policy-eval call couldn't find that file |
| `agent-route`, `agent-merge-gate` | **done** — seeded generic `model-routing.yaml` + `capability-profiles.yaml` (repo-agnostic classes: docs / learning-candidates / agent-workflow / security-secrets / ci-workflows / agent-instructions; generic profiles). Rewrote route's self-test to the generic classes (dropped nix-modules/flake cases) and fixed merge-gate's medium-risk fixture (`flake.nix` → `.agents/schemas/*`). Both self-tests pass standalone |
| `agent-issue-readiness`, `agent-liveness-gate`, `agent-dispatchable-issues`, `agent-review-evidence-check` | **done** — no executable consumer coupling; pass standalone unchanged (`agent-issue-readiness` had a stray `validate.sh` string in a self-test fixture, genericized) |
| `agent-routing-check` | **done** — aligned its hardcoded required path-class / profile id lists to the generic routing classes (dropped `nix-modules`/`nix-engineer`, renamed `agent-workflow-scripts`→`agent-workflow`, `doc-editor`→`doc-agent`, etc.); self-test passes |
| `orchestration/agent-review-pr` | **done** — added a layout-aware `engine_dir()` resolver (honors `AGENT_ENGINE_DIR`, else detects control-plane dir by presence of `agent-merge-gate` across the standalone `scripts/` and consumer `.agents/scripts/` layouts); prompt + fixture genericized. Was the only orchestration script failing standalone |
| `orchestration/agent-run-issue` | **done** — prompt routes validation through `AGENT_VERIFY_CMD` (was `nix-verification-loop` / `scripts/validate.sh` tiers); generic defaults (`AGENT_REPO_DIR` `$HOME/nix`→`$HOME/repo`, `REPO_URL` no nixos default + clone guard); genericized error messages. (`.agents/scripts/agent-*` sibling calls run inside the *target* repo, which is the correct `.agents/` consumer convention.) self-test + shellcheck clean |
| `orchestration/agent-session` | **done** — genericized the nixos-leaky defaults (`AGENT_NAME` `gcp-agent`→`agent`, `AGENT_FQDN` specific tailnet→derives from `AGENT_NAME`, `REMOTE_AGENT_REPO_DIR` `nix`→`repo`), error messages, and header docs. GCE/Tailscale remain as overridable knobs (deployment-specific by nature) |
| `agent-liveness-gate` (follow-up) | genericized a stray `hosts/gcp-agent/CLAUDE.md` reference in a `gh auth` error |

**Executable nixos-coupling sweep across `scripts/` + `orchestration/` is clean.** All 18 scripts pass `--self-test` standalone. Remaining nixos strings are confined to self-test *fixture data* (example `path_classes`/commands inside test JSON), which is illustrative, not functional coupling.
| portable `skills/*` | **done** — genericized prose: `nix-verification-loop`→"the repo's verification-loop skill / verification command", `scripts/validate.sh`→"the repo's verification command", `lib/invariants.nix`→"the repo's invariants/checks", "git-backed flake" note made conditional. `merge-gate` and `CLAUDE.md` kept (generic engine/Claude concepts) |

Each migration sources the lib, replaces hardcoded paths with the `AGENT_*`
vars, and keeps the script's embedded self-test green. Grouped into small PRs by
shared concern (e.g. the outcome-reading family together).

> **Seed gap (being closed):** the policy family was seeded without the
> `governance.yaml` / `model-routing.yaml` / `capability-profiles.yaml` policy
> files they read. Resolution: ship **generic engine-default** policy files at
> the engine root (the scripts' default `<engine>/../<file>` path); consumers
> override with their own copies or `--policy`/`--routing`/`--profiles`.
> **Closed.** `governance.yaml`, `model-routing.yaml`, and
> `capability-profiles.yaml` now ship as generic engine defaults at the engine
> root; the route/merge-gate self-tests were moved to the generic classes in the
> same batch. The whole policy family passes standalone.

## Why this first

Every later v2 capability (dispatcher hardening, real flake outputs, a second
consumer repo) depends on the engine not being hardcoded to one repo. This is
the unblocking step, and it's provable today via the existing self-tests rather
than requiring a live run.
