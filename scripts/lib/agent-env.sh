#!/usr/bin/env bash
# agent-env.sh — single source of truth for the engine's path layout and the
# consumer-config seam. SOURCE this (do not execute it) from engine scripts:
#
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/agent-env.sh"
#
# It resolves two independent roots so the engine stops assuming a `.agents/`
# checkout and runs in either layout:
#
#   AGENT_ENGINE_DIR — where the engine scripts live, derived from THIS file's
#                      location (<engine>/lib/agent-env.sh). Correct whether the
#                      engine is checked out standalone (this repo's scripts/) or
#                      rendered into a consumer's .agents/scripts/. Use it to
#                      locate sibling engine scripts instead of hardcoding paths.
#
#   AGENT_REPO_DIR   — the consumer repo being operated on (git toplevel, else
#                      $PWD). State and learning candidates live under it.
#
# Everything below is consumer-tunable: override any AGENT_* var via the
# environment, or point AGENT_CONFIG at a shell file that sets them (see
# agent.config.example.sh). The defaults match the rendered-into-consumer
# `.agents/` layout so a consumer that adopts the convention needs no config.

# --- engine root (from this lib's own location) ---------------------------
AGENT_ENGINE_DIR="${AGENT_ENGINE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# --- optional consumer config (plain shell; may set any AGENT_* below) -----
if [[ -n ${AGENT_CONFIG:-} && -f ${AGENT_CONFIG} ]]; then
  # shellcheck source=/dev/null
  source "$AGENT_CONFIG"
fi

# --- consumer repo root + state/data layout (consumer-relative) -----------
AGENT_REPO_DIR="${AGENT_REPO_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
AGENT_STATE_DIR="${AGENT_STATE_DIR:-.agents/state}"
AGENT_OUTCOME_DIR="${AGENT_OUTCOME_DIR:-${AGENT_STATE_DIR}/outcomes}"
AGENT_SESSIONS_DIR="${AGENT_SESSIONS_DIR:-${AGENT_STATE_DIR}/sessions}"
AGENT_CANDIDATES_DIR="${AGENT_CANDIDATES_DIR:-.agents/learning/candidates}"

# --- consumer verification entrypoint -------------------------------------
# How the consumer repo proves a change is good. Intentionally EMPTY by default:
# the generic engine cannot know how an arbitrary repo validates itself. The
# nixos-config consumer sets this to its validate.sh; a Node repo might set
# "npm test", etc. This is the seam that replaces the hardcoded
# `scripts/validate.sh` / `nix flake check` references the engine was seeded with.
AGENT_VERIFY_CMD="${AGENT_VERIFY_CMD:-}"

export AGENT_ENGINE_DIR AGENT_REPO_DIR AGENT_STATE_DIR AGENT_OUTCOME_DIR \
  AGENT_SESSIONS_DIR AGENT_CANDIDATES_DIR AGENT_VERIFY_CMD
