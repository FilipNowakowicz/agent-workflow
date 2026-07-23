#!/usr/bin/env bash
# Build a compact TSV routing index for learning candidates.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  index-candidates.sh [root]
  index-candidates.sh --self-test

Builds a compact TSV index of learning candidate files under <root>/candidates
(default root: .agents/learning).
EOF
}

die() {
  printf 'index-candidates: %s\n' "$*" >&2
  exit 1
}

field_from_path() {
  local path=$1
  local name=$2
  sed -n "s/^${name}:[[:space:]]*//p" "$path" | head -1 |
    tr '\t' ' ' |
    sed "s/^\"//; s/\"$//; s/^'//; s/'$//"
}

# Print the TSV index for $1/candidates. Parameterized (rather than reading a
# global root) so --self-test can drive it against throwaway candidate trees.
build_index() {
  local root=$1
  local candidate_dir="$root/candidates"

  printf 'path\tid\tstatus\texpires\ttype\troute\tbest_form\tdedupe_key\ttriggers\ttargets\tevidence\trecurrence\n'

  [ -d "$candidate_dir" ] || return 0

  local candidate_list dedupe_counts
  candidate_list=$(mktemp)
  dedupe_counts=$(mktemp)
  trap 'rm -f "$candidate_list" "$dedupe_counts"' RETURN

  find "$candidate_dir" -maxdepth 1 -type f \( -name '*.md' -o -name '*.yml' -o -name '*.yaml' \) |
    sort >"$candidate_list"

  while IFS= read -r path; do
    local dedupe
    dedupe=$(field_from_path "$path" dedupe_key)
    # Use `if`, not `[ -n ] && printf`: dedupe_key is optional, so when the LAST
    # candidate lacks one the `&&` test is the while body's final command and the
    # loop exits 1, which under `set -euo pipefail` fails this whole pipeline and
    # aborts before the row-emitting loop runs — emitting only the header.
    if [ -n "$dedupe" ]; then
      printf '%s\n' "$dedupe"
    fi
  done <"$candidate_list" |
    sort |
    uniq -c |
    awk '{$1=$1; print}' >"$dedupe_counts"

  while IFS= read -r path; do
    field() {
      field_from_path "$path" "$1"
    }

    local id status expires type route best_form dedupe_key triggers targets evidence recurrence
    id=$(field id)
    status=$(field status)
    expires=$(field expires)
    type=$(field type)
    route=$(field route)
    best_form=$(field best_form)
    dedupe_key=$(field dedupe_key)
    triggers=$(field triggers)
    targets=$(field targets)
    evidence=$(field evidence)
    recurrence=1
    if [ -n "$dedupe_key" ]; then
      recurrence=$(awk -v key="$dedupe_key" '$0 ~ /^[0-9]+ / { count=$1; $1=""; sub(/^ /, ""); if ($0 == key) print count }' "$dedupe_counts" | head -1)
      [ -n "$recurrence" ] || recurrence=1
    fi

    [ -n "$id" ] || id=$(basename "$path")
    [ -n "$status" ] || status=unknown

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$path" "$id" "$status" "$expires" "$type" "$route" "$best_form" \
      "$dedupe_key" "$triggers" "$targets" "$evidence" "$recurrence"
  done <"$candidate_list"
}

self_test() {
  local tmp
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN

  # Extract column $2 (1-based) from single-line TSV row $1.
  col() {
    printf '%s\n' "$1" | cut -f"$2"
  }

  # The data row whose id column (2) equals $2, out of full index output $1.
  row_for() {
    awk -F'\t' -v id="$2" '$2 == id' <<<"$1"
  }

  # Case 1: fully populated candidate -> every column lands correctly.
  mkdir -p "$tmp/full/candidates"
  cat >"$tmp/full/candidates/full.yml" <<'EOF'
id: cand-full
status: open
expires: 2026-09-01
type: repo-fix
route: implement-fix
best_form: test
dedupe_key: key-full
triggers: trigger-a
targets: some/file.sh
evidence: PR-#1
EOF
  local out row
  out=$(build_index "$tmp/full")
  row=$(row_for "$out" cand-full)
  [ -n "$row" ] || die "self-test: full candidate produced no row"
  [ "$(col "$row" 1)" = "$tmp/full/candidates/full.yml" ] || die "self-test: full candidate path column wrong (got: $(col "$row" 1))"
  [ "$(col "$row" 3)" = "open" ] || die "self-test: full candidate status column wrong"
  [ "$(col "$row" 4)" = "2026-09-01" ] || die "self-test: full candidate expires column wrong"
  [ "$(col "$row" 5)" = "repo-fix" ] || die "self-test: full candidate type column wrong"
  [ "$(col "$row" 6)" = "implement-fix" ] || die "self-test: full candidate route column wrong"
  [ "$(col "$row" 7)" = "test" ] || die "self-test: full candidate best_form column wrong"
  [ "$(col "$row" 8)" = "key-full" ] || die "self-test: full candidate dedupe_key column wrong"
  [ "$(col "$row" 9)" = "trigger-a" ] || die "self-test: full candidate triggers column wrong"
  [ "$(col "$row" 10)" = "some/file.sh" ] || die "self-test: full candidate targets column wrong"
  [ "$(col "$row" 11)" = "PR-#1" ] || die "self-test: full candidate evidence column wrong"
  [ "$(col "$row" 12)" = "1" ] || die "self-test: full candidate with no shared dedupe_key should have recurrence 1"

  # Case 2: candidate missing optional fields (no dedupe_key), and it is the
  # LAST candidate alphabetically -- must still produce a row (the pipefail
  # edge case documented above build_index's dedupe pass) with recurrence
  # defaulting to 1 and empty columns for the missing fields.
  mkdir -p "$tmp/missing-optional/candidates"
  cat >"$tmp/missing-optional/candidates/a-first.yml" <<'EOF'
id: cand-first
status: open
dedupe_key: unrelated-key
EOF
  cat >"$tmp/missing-optional/candidates/z-last.yml" <<'EOF'
id: cand-last
status: open
EOF
  out=$(build_index "$tmp/missing-optional")
  row=$(row_for "$out" cand-first)
  [ -n "$row" ] || die "self-test: candidate preceding the missing-dedupe entry produced no row"
  row=$(row_for "$out" cand-last)
  [ -n "$row" ] || die "self-test: last candidate missing dedupe_key produced no row -- pipeline aborted early"
  [ "$(col "$row" 8)" = "" ] || die "self-test: missing dedupe_key column should be empty"
  [ "$(col "$row" 5)" = "" ] || die "self-test: missing type column should be empty"
  [ "$(col "$row" 9)" = "" ] || die "self-test: missing triggers column should be empty"
  [ "$(col "$row" 12)" = "1" ] || die "self-test: missing dedupe_key should default recurrence to 1"

  # Case 3: two candidates sharing a dedupe_key -> both rows show recurrence
  # equal to the count of candidates sharing that key.
  mkdir -p "$tmp/shared-dedupe/candidates"
  cat >"$tmp/shared-dedupe/candidates/one.yml" <<'EOF'
id: cand-one
status: open
dedupe_key: shared-key
EOF
  cat >"$tmp/shared-dedupe/candidates/two.yml" <<'EOF'
id: cand-two
status: open
dedupe_key: shared-key
EOF
  out=$(build_index "$tmp/shared-dedupe")
  row=$(row_for "$out" cand-one)
  [ "$(col "$row" 12)" = "2" ] || die "self-test: shared dedupe_key recurrence wrong for cand-one (got: $(col "$row" 12))"
  row=$(row_for "$out" cand-two)
  [ "$(col "$row" 12)" = "2" ] || die "self-test: shared dedupe_key recurrence wrong for cand-two (got: $(col "$row" 12))"

  # Case 4: candidate file missing id -> row falls back to the file's
  # basename as id.
  mkdir -p "$tmp/missing-id/candidates"
  cat >"$tmp/missing-id/candidates/no-id.yml" <<'EOF'
status: open
EOF
  out=$(build_index "$tmp/missing-id")
  row=$(row_for "$out" no-id.yml)
  [ -n "$row" ] || die "self-test: missing-id candidate did not fall back to basename"

  # Case 4b: candidate file missing status -> status column falls back to
  # "unknown" (not empty), matching the id-fallback behavior above.
  mkdir -p "$tmp/missing-status/candidates"
  cat >"$tmp/missing-status/candidates/no-status.yml" <<'EOF'
id: cand-no-status
EOF
  out=$(build_index "$tmp/missing-status")
  row=$(row_for "$out" cand-no-status)
  [ -n "$row" ] || die "self-test: missing-status candidate produced no row"
  [ "$(col "$row" 3)" = "unknown" ] || die "self-test: missing status column should default to 'unknown' (got: $(col "$row" 3))"

  # Case 5: missing candidates/ directory -> only the header line, exit 0.
  local rc
  out=$(build_index "$tmp/no-such-root") && rc=0 || rc=$?
  [ "$rc" -eq 0 ] || die "self-test: missing candidates dir should exit 0 (rc=$rc)"
  [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] || die "self-test: missing candidates dir should print only the header (got: $out)"

  # Case 5b: empty candidates/ directory -> same, header only, exit 0.
  mkdir -p "$tmp/empty-dir/candidates"
  out=$(build_index "$tmp/empty-dir") && rc=0 || rc=$?
  [ "$rc" -eq 0 ] || die "self-test: empty candidates dir should exit 0 (rc=$rc)"
  [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] || die "self-test: empty candidates dir should print only the header (got: $out)"

  printf 'index-candidates self-test passed\n'
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
build_index "$root"
