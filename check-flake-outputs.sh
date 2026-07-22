#!/usr/bin/env bash
# Local smoke test for this repo's flake `paths` output (issue #30): proves
# every exported path resolves to a real, non-empty directory containing at
# least one expected marker file, so a consumer pinning this repo as a flake
# input gets something real rather than a dangling or empty tree.
#
# Reads the path list from `nix eval` against the flake itself (not a
# hard-coded copy of flake.nix's `paths` attrset), so this check cannot drift
# out of sync with the actual exported output shape.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: check-flake-outputs.sh [--flake <path-or-url>]
       check-flake-outputs.sh --self-test

Verify every entry of this flake's `paths` output exists, is non-empty, and
contains at least one expected marker file.

Options:
  --flake <path-or-url>  Flake reference to check (default: . — this repo).
  --self-test            Run a deterministic self-test and exit.
  -h, --help             Show this help.
EOF
}

die() {
  printf 'check-flake-outputs: %s\n' "$*" >&2
  exit 1
}

script_dir() {
  CDPATH='' cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

# Marker files relative to each `paths` attribute, proving the directory
# is the real source tree and not an empty/decoy one. Keep in lockstep with
# flake.nix's `paths` attrset and this repo's actual layout.
marker_for() {
  case "$1" in
  skills) printf 'issue-tdd/SKILL.md\n' ;;
  orchestration) printf 'agent-run-issue.sh\n' ;;
  controlPlane) printf 'agent-route\n' ;;
  schemas) printf 'outcome.schema.json\n' ;;
  repoMap) printf 'README.md\n' ;;
  learning) printf 'README.md\n' ;;
  canaries) printf 'README.md\n' ;;
  *) printf '\n' ;;
  esac
}

check_paths() {
  local flake_ref="$1"
  command -v nix >/dev/null 2>&1 || die "nix not found"

  local paths_json err_file
  err_file=$(mktemp)
  if ! paths_json=$(nix eval --json "${flake_ref}#paths" \
    --apply 'builtins.mapAttrs (n: v: toString v)' 2>"$err_file"); then
    die "failed to evaluate ${flake_ref}#paths: $(cat "$err_file")"
  fi
  rm -f "$err_file"

  command -v jq >/dev/null 2>&1 || die "jq not found"

  local name dir marker failed=0
  for name in $(printf '%s' "$paths_json" | jq -r 'keys[]'); do
    dir=$(printf '%s' "$paths_json" | jq -r --arg n "$name" '.[$n]')
    if [[ ! -d $dir ]]; then
      echo "check-flake-outputs: paths.$name ($dir) is not a directory" >&2
      failed=1
      continue
    fi
    if [[ -z $(find "$dir" -mindepth 1 -print -quit) ]]; then
      echo "check-flake-outputs: paths.$name ($dir) is empty" >&2
      failed=1
      continue
    fi
    marker="$(marker_for "$name")"
    if [[ -n $marker && ! -e "$dir/$marker" ]]; then
      echo "check-flake-outputs: paths.$name ($dir) is missing expected marker file: $marker" >&2
      failed=1
      continue
    fi
    echo "check-flake-outputs: paths.$name -> $dir (ok)" >&2
  done

  [[ $failed -eq 0 ]] || die "one or more exported paths failed validation"
  echo "check-flake-outputs: all exported paths validated" >&2
}

self_test() {
  command -v nix >/dev/null 2>&1 || die "self-test: nix not found"
  local script_path
  script_path="$(script_dir)/$(basename "${BASH_SOURCE[0]}")"

  # The real flake passes.
  "$script_path" --flake "$(script_dir)" >/dev/null 2>&1 ||
    die "self-test: expected the real flake's paths output to validate cleanly"

  # A flake whose paths output points at an empty directory is rejected.
  local tmp
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/empty-dir"
  cat >"$tmp/flake.nix" <<'EOF'
{
  outputs = { self }: {
    paths = {
      empty = ./empty-dir;
    };
  };
}
EOF
  if "$script_path" --flake "$tmp" >/dev/null 2>&1; then
    die "self-test: expected an empty exported path to fail validation"
  fi

  printf 'check-flake-outputs self-test passed\n'
}

flake_ref="."
while [[ $# -gt 0 ]]; do
  case "$1" in
  --flake)
    flake_ref="${2:?--flake needs a value}"
    shift 2
    ;;
  --self-test)
    self_test
    exit 0
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    die "unknown argument: $1"
    ;;
  esac
done

check_paths "$flake_ref"
