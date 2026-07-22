#!/usr/bin/env bash
# Render this provider repo's source trees into a consumer repo's installed
# .agents/ layout (see docs/provider-consumer-layout.md), plus root
# scripts/agent-*.sh orchestration entrypoints. This is the "installer
# script" half of the flake/install consumption contract (issue #30); the
# flake's `paths` output is the other half — see examples/consumer-flake/
# for how a consumer pins this repo and locates --source from a flake input.
#
# This only copies files; it never touches git history, never overwrites an
# existing file without --force, and never runs anything from the source
# tree. It is safe to re-run.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install.sh --target <consumer-repo-dir> [--source <agent-workflow-checkout>] [--force]
       install.sh --self-test

Install this provider repo's skills/scripts/schemas/learning/repo-map/
canaries trees under <target>/.agents/, and orchestration/*.sh as root-level
<target>/scripts/agent-*.sh entrypoints.

Options:
  --target <dir>  Consumer repo root to install into (required).
  --source <dir>  This repo's checkout to install from (default: the
                   directory containing this script).
  --force         Overwrite an existing .agents/ subtree / entrypoint
                   instead of refusing when one is already present.
  --self-test     Run a deterministic, offline self-test and exit.
  -h, --help      Show this help.

governance.yaml, model-routing.yaml, and capability-profiles.yaml are
installed as <target>/.agents/*.yaml.example, not as the live files: their
path-class patterns are shaped for this provider repo's own layout and must
be rewritten for the consumer repo's layout before use (see
docs/provider-consumer-layout.md). Rename the .example file and edit it once
you are ready to opt in.
EOF
}

die() {
  printf 'install.sh: %s\n' "$*" >&2
  exit 1
}

script_dir() {
  CDPATH='' cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

# Replace <target>/<dest_rel> with a copy of <source>/<src_rel>. Refuses if
# the destination already exists unless $force is set.
install_tree() {
  local source="$1" target="$2" src_rel="$3" dest_rel="$4" force="$5"
  local src="$source/$src_rel" dest="$target/$dest_rel"
  [[ -d $src ]] || die "source tree not found: $src"
  if [[ -e $dest && $force -ne 1 ]]; then
    die "$dest already exists (pass --force to overwrite)"
  fi
  mkdir -p "$(dirname "$dest")"
  rm -rf "$dest"
  cp -r "$src" "$dest"
}

install_file() {
  local source="$1" target="$2" src_rel="$3" dest_rel="$4" force="$5"
  local src="$source/$src_rel" dest="$target/$dest_rel"
  [[ -f $src ]] || die "source file not found: $src"
  if [[ -e $dest && $force -ne 1 ]]; then
    die "$dest already exists (pass --force to overwrite)"
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
}

run_install() {
  local source="$1" target="$2" force="$3"

  [[ -d $target ]] || die "--target directory does not exist: $target"

  install_tree "$source" "$target" skills .agents/skills "$force"
  install_tree "$source" "$target" scripts .agents/scripts "$force"
  install_tree "$source" "$target" schemas .agents/schemas "$force"
  install_tree "$source" "$target" learning .agents/learning "$force"
  install_tree "$source" "$target" repo-map .agents/repo-map "$force"
  install_tree "$source" "$target" canaries .agents/canaries "$force"
  mkdir -p "$target/.agents/state/outcomes" "$target/.agents/state/sessions" "$target/.agents/state/review" "$target/.agents/state/freezes"

  local f base
  for f in "$source"/orchestration/*.sh; do
    [[ -f $f ]] || continue
    base="$(basename "$f")"
    install_file "$source" "$target" "orchestration/$base" "scripts/$base" "$force"
  done

  install_file "$source" "$target" governance.yaml .agents/governance.yaml.example "$force"
  install_file "$source" "$target" model-routing.yaml .agents/model-routing.yaml.example "$force"
  install_file "$source" "$target" capability-profiles.yaml .agents/capability-profiles.yaml.example "$force"

  echo "install.sh: installed agent-workflow into $target/.agents and $target/scripts" >&2
  echo "install.sh: review and rename the .agents/*.yaml.example files before opting into policy gating" >&2
}

self_test() {
  local script_path
  script_path="$(script_dir)/$(basename "${BASH_SOURCE[0]}")"
  local source target
  source=$(mktemp -d)
  target=$(mktemp -d)
  trap 'rm -rf "$source" "$target"' RETURN

  mkdir -p "$source/skills/foo" "$source/scripts" "$source/schemas" "$source/learning" "$source/repo-map" "$source/canaries" "$source/orchestration"
  printf 'stub\n' >"$source/skills/foo/SKILL.md"
  printf '#!/usr/bin/env bash\n' >"$source/scripts/agent-stub"
  printf '{}\n' >"$source/schemas/stub.schema.json"
  printf 'stub\n' >"$source/learning/README.md"
  printf 'stub\n' >"$source/repo-map/README.md"
  printf 'stub\n' >"$source/canaries/README.md"
  printf '#!/usr/bin/env bash\n' >"$source/orchestration/agent-stub-session.sh"
  printf 'version: 1\ndefault:\n  risk: low\n  requires_human_review: false\n  reason: ""\n' >"$source/governance.yaml"
  printf 'schema: agent-model-routing/v1\nversion: 1\npath_classes: []\n' >"$source/model-routing.yaml"
  printf 'schema: agent-capability-profiles/v1\nversion: 1\nprofiles: []\n' >"$source/capability-profiles.yaml"

  "$script_path" --source "$source" --target "$target" >/dev/null 2>&1 ||
    die "self-test: expected a fresh install to succeed"

  [[ -f "$target/.agents/skills/foo/SKILL.md" ]] || die "self-test: skills tree was not installed"
  [[ -f "$target/.agents/scripts/agent-stub" ]] || die "self-test: scripts tree was not installed"
  [[ -f "$target/.agents/canaries/README.md" ]] || die "self-test: canaries tree was not installed"
  [[ -f "$target/scripts/agent-stub-session.sh" ]] || die "self-test: orchestration entrypoint was not installed at root scripts/"
  [[ -d "$target/.agents/state/outcomes" ]] || die "self-test: state directory structure was not created"
  [[ -d "$target/.agents/state/freezes" ]] || die "self-test: freezes state directory was not created"
  [[ -f "$target/.agents/governance.yaml.example" ]] || die "self-test: governance.yaml was not installed as .example"
  [[ ! -e "$target/.agents/governance.yaml" ]] || die "self-test: governance.yaml must not be installed as a live file"

  # Re-running without --force refuses to clobber an existing install.
  if "$script_path" --source "$source" --target "$target" >/dev/null 2>&1; then
    die "self-test: expected a second install without --force to fail"
  fi

  # --force allows re-installing.
  "$script_path" --source "$source" --target "$target" --force >/dev/null 2>&1 ||
    die "self-test: expected --force to allow re-installing"

  printf 'install.sh self-test passed\n'
}

target="" source="$(script_dir)" force=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  --target)
    target="${2:?--target needs a value}"
    shift 2
    ;;
  --source)
    source="${2:?--source needs a value}"
    shift 2
    ;;
  --force)
    force=1
    shift
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

[[ -n $target ]] || die "--target is required (see --help)"
run_install "$source" "$target" "$force"
