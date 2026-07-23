#!/usr/bin/env bash
# Query the compact candidate index without opening candidate bodies.
#
# Usage:
#   query-candidates.sh <query terms...>
#   query-candidates.sh --self-test
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$script_dir/.." && pwd)

usage() {
  printf 'usage: %s <query terms...>\n' "$(basename "$0")" >&2
}

die() {
  printf 'query-candidates: %s\n' "$*" >&2
  exit 1
}

# Score candidates under $root/candidates against $* (query terms) by how many
# terms appear (case-insensitively) anywhere in each TSV row, breaking ties by
# recurrence (the last column), and print the header plus the top 5 matches.
# Parameterized by root (rather than reading the global $root) so --self-test
# can drive it against a throwaway candidates tree without touching real
# learning/candidates.
query() {
  local root=$1
  shift
  local query=$*
  local tmp
  tmp=${TMPDIR:-/tmp}/learning-index-$$.tsv
  trap 'rm -f "$tmp"' RETURN

  "$script_dir/index-candidates.sh" "$root" >"$tmp"

  {
    head -1 "$tmp"
    tail -n +2 "$tmp" |
      awk -F "\t" -v query="$query" '
        BEGIN {
          n = split(tolower(query), terms, /[[:space:]]+/)
        }
        {
          line = tolower($0)
          score = 0
          for (i = 1; i <= n; i++) {
            if (terms[i] != "" && index(line, terms[i]) > 0) {
              score++
            }
          }
          if (score > 0) {
            recurrence = $NF
            if (recurrence !~ /^[0-9]+$/) {
              recurrence = 1
            }
            print score "\t" recurrence "\t" $0
          }
        }
      ' |
      sort -t "$(printf '\t')" -k1,1rn -k2,2rn |
      cut -f3- ||
      true
  } |
    head -6
}

self_test() {
  local tmp out rc
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN

  # Case 1: query terms all appear in one candidate's row, only partially in
  # another -> the full-match candidate ranks first.
  mkdir -p "$tmp/full-vs-partial/candidates"
  cat >"$tmp/full-vs-partial/candidates/full-match.yml" <<'EOF'
id: full-match
status: open
route: implement-fix
best_form: test
evidence: PR-#1
triggers: xylophone quokka
EOF
  cat >"$tmp/full-vs-partial/candidates/partial-match.yml" <<'EOF'
id: partial-match
status: open
route: implement-fix
best_form: test
evidence: PR-#2
triggers: xylophone
EOF
  out=$(query "$tmp/full-vs-partial" xylophone quokka)
  [[ $(sed -n '2p' <<<"$out") == *full-match* ]] ||
    die "self-test: full-match candidate should rank first (got: $out)"
  [[ $(sed -n '3p' <<<"$out") == *partial-match* ]] ||
    die "self-test: partial-match candidate should rank second (got: $out)"

  # Case 2: equal term-match score, different recurrence via shared
  # dedupe_key -> the higher-recurrence candidate ranks first.
  mkdir -p "$tmp/recurrence/candidates"
  cat >"$tmp/recurrence/candidates/high-recurrence.yml" <<'EOF'
id: high-recurrence
status: open
route: implement-fix
best_form: test
evidence: PR-#3
dedupe_key: shared-key
triggers: foobar42
EOF
  cat >"$tmp/recurrence/candidates/dedupe-sibling.yml" <<'EOF'
id: dedupe-sibling
status: open
route: implement-fix
best_form: test
evidence: PR-#4
dedupe_key: shared-key
triggers: unrelated-term
EOF
  cat >"$tmp/recurrence/candidates/low-recurrence.yml" <<'EOF'
id: low-recurrence
status: open
route: implement-fix
best_form: test
evidence: PR-#5
dedupe_key: unique-key
triggers: foobar42
EOF
  out=$(query "$tmp/recurrence" foobar42)
  [[ $(sed -n '2p' <<<"$out") == *high-recurrence* ]] ||
    die "self-test: higher-recurrence candidate should rank first (got: $out)"
  [[ $(sed -n '3p' <<<"$out") == *low-recurrence* ]] ||
    die "self-test: lower-recurrence candidate should rank second (got: $out)"
  [[ $out != *dedupe-sibling* ]] ||
    die "self-test: non-matching dedupe sibling should not appear in results"

  # Case 3: more than 5 matching candidates -> truncated to top 5 plus the
  # header line (never more than 6 lines total).
  mkdir -p "$tmp/truncation/candidates"
  for i in 1 2 3 4 5 6 7; do
    cat >"$tmp/truncation/candidates/cand-$i.yml" <<EOF
id: cand-$i
status: open
route: implement-fix
best_form: test
evidence: PR-#$i
triggers: commonterm7
EOF
  done
  out=$(query "$tmp/truncation" commonterm7)
  [[ $(wc -l <<<"$out") -eq 6 ]] ||
    die "self-test: output should be truncated to header + top 5 (got $(wc -l <<<"$out") lines)"

  # Case 4: a query matching nothing -> only the header line is printed,
  # exit 0 (not an error).
  mkdir -p "$tmp/no-match/candidates"
  cat >"$tmp/no-match/candidates/example.yml" <<'EOF'
id: example
status: open
route: implement-fix
best_form: test
evidence: PR-#6
triggers: something
EOF
  out=$(query "$tmp/no-match" zzznomatchterm99) && rc=0 || rc=$?
  [[ $rc -eq 0 ]] || die "self-test: no-match query should exit 0 (rc=$rc)"
  [[ $(wc -l <<<"$out") -eq 1 ]] ||
    die "self-test: no-match query should print only the header (got: $out)"

  # Case 5: no query arguments at all -> the script's existing usage/exit-2
  # behavior is preserved.
  "$0" >/dev/null 2>&1 && rc=0 || rc=$?
  [[ $rc -eq 2 ]] || die "self-test: no-args invocation should exit 2 (rc=$rc)"

  printf 'query-candidates self-test passed\n'
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

if [ "$#" -eq 0 ]; then
  usage
  exit 2
fi

query "$root" "$@"
