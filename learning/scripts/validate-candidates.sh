#!/usr/bin/env bash
# Validate compact learning-candidate routing metadata.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  validate-candidates.sh [root]
  validate-candidates.sh --self-test

Validates compact-YAML learning candidate files under <root>/candidates
(default root: .agents/learning).
EOF
}

die() {
  printf 'validate-candidates: %s\n' "$*" >&2
  exit 1
}

# Minimal set a reviewer needs to triage and reopen the source. Everything
# else (agent, type, dedupe_key, triggers, targets, risk) is optional and only
# improves routing when present — keep capture cheap.
required_fields=(
  schema
  id
  date
  expires
  status
  route
  best_form
  evidence
  observation
  proposed_upgrade
)

allowed_type='^(behavior-upgrade|repo-fix|workflow-gotcha|policy-gap)$'
allowed_route='^(implement-fix|promote-memory|promote-skill|promote-hook|promote-doc|reject)$'
allowed_best_form='^(invariant|test|ci-gate|hook|skill|doc|none)$'
allowed_status='^(open|promoted|rejected|superseded|expired)$'

validate() {
  local root="$1"
  local candidate_dir="$root/candidates"
  local rc=0

  [ -d "$candidate_dir" ] || return 0

  while IFS= read -r path; do
    case "$path" in
    *.yml | *.yaml) ;;
    *)
      printf 'learning candidate must be compact YAML: %s\n' "$path" >&2
      rc=1
      continue
      ;;
    esac

    for field in "${required_fields[@]}"; do
      if ! grep -Eq "^${field}:" "$path"; then
        printf '%s: missing required field %s\n' "$path" "$field" >&2
        rc=1
      fi
    done

    # Candidates are single-line compact YAML. Flag any top-level key written
    # block-style (value on the next line) — required or optional — so the index
    # scripts' same-line grep never silently drops a field.
    while IFS= read -r key; do
      printf '%s: field %s must be single-line compact YAML (value on the same line as the key)\n' "$path" "${key%%:*}" >&2
      rc=1
    done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*$' "$path")

    if ! grep -Eq '^schema:[[:space:]]*learning-candidate/v1$' "$path"; then
      printf '%s: schema must be learning-candidate/v1\n' "$path" >&2
      rc=1
    fi

    if ! sed -n 's/^status:[[:space:]]*//p' "$path" | head -1 | grep -Eq "$allowed_status"; then
      printf '%s: invalid status\n' "$path" >&2
      rc=1
    fi

    # type is optional; validate only when present.
    if grep -Eq '^type:[[:space:]]*.+' "$path" &&
      ! sed -n 's/^type:[[:space:]]*//p' "$path" | head -1 | grep -Eq "$allowed_type"; then
      printf '%s: invalid type\n' "$path" >&2
      rc=1
    fi

    if ! sed -n 's/^route:[[:space:]]*//p' "$path" | head -1 | grep -Eq "$allowed_route"; then
      printf '%s: invalid route\n' "$path" >&2
      rc=1
    fi

    if ! sed -n 's/^best_form:[[:space:]]*//p' "$path" | head -1 | grep -Eq "$allowed_best_form"; then
      printf '%s: invalid best_form\n' "$path" >&2
      rc=1
    fi
  done < <(find "$candidate_dir" -maxdepth 1 -type f ! -name '.gitkeep' | sort)

  return "$rc"
}

self_test() {
  local tmp out rc
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN

  # Case 1: fully valid compact-YAML candidate -> exit 0, no output.
  mkdir -p "$tmp/valid/candidates"
  cat >"$tmp/valid/candidates/example.yml" <<'EOF'
schema: learning-candidate/v1
id: example
date: 2026-06-01
expires: 2026-09-01
status: open
route: implement-fix
best_form: test
evidence: PR-#1
observation: something happened
proposed_upgrade: do the thing
EOF
  out=$(validate "$tmp/valid" 2>&1) && rc=0 || rc=$?
  [[ $rc -eq 0 ]] || die "self-test: valid candidate should exit 0 (rc=$rc, out=$out)"
  [[ -z $out ]] || die "self-test: valid candidate should produce no output (got: $out)"

  # Case 2: missing a required field (evidence) -> exit 1, names the field.
  mkdir -p "$tmp/missing-field/candidates"
  cat >"$tmp/missing-field/candidates/example.yml" <<'EOF'
schema: learning-candidate/v1
id: example
date: 2026-06-01
expires: 2026-09-01
status: open
route: implement-fix
best_form: test
observation: something happened
proposed_upgrade: do the thing
EOF
  out=$(validate "$tmp/missing-field" 2>&1) && rc=0 || rc=$?
  [[ $rc -eq 1 ]] || die "self-test: missing field should exit 1 (rc=$rc)"
  grep -Fq 'missing required field evidence' <<<"$out" ||
    die "self-test: missing-field message did not name the field (got: $out)"

  # Case 3: invalid status -> exit 1, identifies the bad field.
  mkdir -p "$tmp/bad-status/candidates"
  cat >"$tmp/bad-status/candidates/example.yml" <<'EOF'
schema: learning-candidate/v1
id: example
date: 2026-06-01
expires: 2026-09-01
status: not-a-real-status
route: implement-fix
best_form: test
evidence: PR-#1
observation: something happened
proposed_upgrade: do the thing
EOF
  out=$(validate "$tmp/bad-status" 2>&1) && rc=0 || rc=$?
  [[ $rc -eq 1 ]] || die "self-test: invalid status should exit 1 (rc=$rc)"
  grep -Fq 'invalid status' <<<"$out" ||
    die "self-test: invalid-status message did not identify the field (got: $out)"

  # Case 4: a block-style (multi-line) field value -> exit 1, flagged as such.
  mkdir -p "$tmp/block-style/candidates"
  cat >"$tmp/block-style/candidates/example.yml" <<'EOF'
schema: learning-candidate/v1
id: example
date: 2026-06-01
expires: 2026-09-01
status: open
route: implement-fix
best_form: test
evidence:
  - PR-#1
observation: something happened
proposed_upgrade: do the thing
EOF
  out=$(validate "$tmp/block-style" 2>&1) && rc=0 || rc=$?
  [[ $rc -eq 1 ]] || die "self-test: block-style field should exit 1 (rc=$rc)"
  grep -Fq 'must be single-line compact YAML' <<<"$out" ||
    die "self-test: block-style field was not flagged (got: $out)"

  printf 'validate-candidates self-test passed\n'
}

case "${1:-}" in
--self-test)
  self_test
  exit 0
  ;;
-h | --help)
  usage
  exit 0
  ;;
esac

root=${1:-.agents/learning}
validate "$root"
