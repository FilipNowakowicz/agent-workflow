# shellcheck shell=bash
# agent.config.example.sh — example consumer config for the agent-workflow engine.
#
# Copy to your consumer repo (e.g. agent.config.sh), set the knobs your repo
# needs, and point the engine at it:
#
#   AGENT_CONFIG=/path/to/agent.config.sh <engine>/scripts/agent-dispatch ...
#
# This file is plain shell sourced by scripts/lib/agent-env.sh. It holds the
# consumer-LOCAL bits the engine must not hardcode (PLAN.md §22: consumer keeps
# local repo map, risk policy, verification commands, host runbooks).

# How this repo proves a change is good. The engine runs this; it never assumes
# a Nix toolchain. Examples:
#   AGENT_VERIFY_CMD="bash scripts/validate.sh flake-eval"   # nixos-config
#   AGENT_VERIFY_CMD="npm test && npm run lint"              # a Node repo
# shellcheck disable=SC2034  # consumed by scripts/lib/agent-env.sh after sourcing
AGENT_VERIFY_CMD="bash scripts/validate.sh flake-eval"

# Where this repo keeps agent state + learning candidates. Defaults already
# match the `.agents/` convention; override only if your repo differs.
# AGENT_STATE_DIR=".agents/state"
# AGENT_CANDIDATES_DIR=".agents/learning/candidates"
