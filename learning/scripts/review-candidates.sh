#!/usr/bin/env bash
# Summarize learning candidates for reviewer triage without opening bodies.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

usage() {
  cat <<'EOF'
Usage:
  review-candidates.sh [root]
  review-candidates.sh --self-test

Builds a reviewer-triage summary from the candidate index under
<root>/candidates (default root: .agents/learning).
EOF
}

die() {
  printf 'review-candidates: %s\n' "$*" >&2
  exit 1
}

review() {
  local root=${1:-.agents/learning}
  local today=${LEARNING_TODAY:-$(date +%F)}
  local tmp
  tmp=${TMPDIR:-/tmp}/learning-review-$$.tsv
  trap 'rm -f "$tmp"' RETURN

  "$script_dir/index-candidates.sh" "$root" >"$tmp"

  printf 'Learning candidate review index (%s)\n\n' "$today"

  printf 'Status counts:\n'
  tail -n +2 "$tmp" |
    awk -F '\t' '{ count[$3 == "" ? "unknown" : $3]++ } END { for (k in count) print count[k], k }' |
    sort -k2

  printf '\nOpen candidates by route/form:\n'
  tail -n +2 "$tmp" |
    awk -F '\t' '$3 == "open" { key = ($6 == "" ? "unknown" : $6) "/" ($7 == "" ? "unknown" : $7); count[key]++ } END { for (k in count) print count[k], k }' |
    sort -k2

  printf '\nTop recurring open candidates:\n'
  tail -n +2 "$tmp" |
    awk -F '\t' '$3 == "open" && $12 > 1 { print $12 "\t" $8 "\t" $2 "\t" $1 }' |
    sort -t "$(printf '\t')" -k1,1rn -k2,2 -k3,3 |
    awk -F '\t' 'NR<=10 { print "captured " $1 " times\t" $2 "\t" $3 "\t" $4 }'

  printf '\nExpired open candidates:\n'
  tail -n +2 "$tmp" |
    awk -F '\t' -v today="$today" '$3 == "open" && $4 != "" && $4 < today { print $1 "\t" $2 "\t" $4 "\t" $6 "/" $7 }' |
    sort -k3 ||
    true

  printf '\nOpen candidate rows:\n'
  head -1 "$tmp"
  tail -n +2 "$tmp" |
    awk -F '\t' '$3 == "open"' |
    sort -t "$(printf '\t')" -k6,6 -k7,7 -k12,12rn -k4,4 -k2,2
}

candidate() {
  local dir=$1
  local file=$2
  shift 2
  mkdir -p "$dir/candidates"
  {
    printf 'schema: learning-candidate/v1\n'
    printf 'id: %s\n' "$file"
    printf 'date: 2026-01-01\n'
    printf 'evidence: PR-#1\n'
    printf 'observation: something happened\n'
    printf 'proposed_upgrade: do the thing\n'
    printf '%s\n' "$@"
  } >"$dir/candidates/$file.yml"
}

self_test() {
  local tmp out rc
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN

  # Not-yet-expired open candidate, unique group, no recurrence.
  candidate "$tmp" c1-open-formA \
    'status: open' 'expires: 2099-01-01' \
    'route: implement-fix' 'best_form: test'

  # Expired open candidate, unique group, no recurrence.
  candidate "$tmp" c2-open-formB \
    'status: open' 'expires: 2020-01-01' \
    'route: promote-skill' 'best_form: skill'

  # Expired but promoted (not open) -> must not appear as an expired-open row.
  candidate "$tmp" c3-promoted \
    'status: promoted' 'expires: 2020-01-01' \
    'route: implement-fix' 'best_form: test'

  # Recurrence-3 group, open, one member expired (to also test the expired
  # section alongside a recurring group).
  candidate "$tmp" c4-open-recurring-a \
    'status: open' 'expires: 2020-02-01' \
    'route: promote-doc' 'best_form: doc' 'dedupe_key: dupe-high'
  candidate "$tmp" c5-open-recurring-b \
    'status: open' 'expires: 2099-01-01' \
    'route: promote-doc' 'best_form: doc' 'dedupe_key: dupe-high'
  candidate "$tmp" c6-open-recurring-c \
    'status: open' 'expires: 2099-01-01' \
    'route: promote-doc' 'best_form: doc' 'dedupe_key: dupe-high'

  # Recurrence-2 group, open.
  candidate "$tmp" c7-open-recurring-x \
    'status: open' 'expires: 2099-01-01' \
    'route: promote-hook' 'best_form: hook' 'dedupe_key: dupe-low'
  candidate "$tmp" c8-open-recurring-y \
    'status: open' 'expires: 2099-01-01' \
    'route: promote-hook' 'best_form: hook' 'dedupe_key: dupe-low'

  # Recurrence-2 group, but rejected (not open) -> must be excluded from the
  # top-recurring-open section entirely.
  candidate "$tmp" c9-rejected-recurring-a \
    'status: rejected' 'expires: 2099-01-01' \
    'route: reject' 'best_form: none' 'dedupe_key: dupe-rejected'
  candidate "$tmp" c10-rejected-recurring-b \
    'status: rejected' 'expires: 2099-01-01' \
    'route: reject' 'best_form: none' 'dedupe_key: dupe-rejected'

  out=$(LEARNING_TODAY=2026-06-01 review "$tmp")

  # Status counts: 7 open, 1 promoted, 2 rejected.
  grep -Fq $'7 open' <<<"$out" || die "self-test: status counts missing 7 open (got: $out)"
  grep -Fq $'1 promoted' <<<"$out" || die "self-test: status counts missing 1 promoted"
  grep -Fq $'2 rejected' <<<"$out" || die "self-test: status counts missing 2 rejected"

  # Open candidates by route/form: only status:open counted, grouped correctly.
  grep -Fq '1 implement-fix/test' <<<"$out" || die "self-test: route/form group implement-fix/test wrong"
  grep -Fq '1 promote-skill/skill' <<<"$out" || die "self-test: route/form group promote-skill/skill wrong"
  grep -Fq '3 promote-doc/doc' <<<"$out" || die "self-test: route/form group promote-doc/doc wrong"
  grep -Fq '2 promote-hook/hook' <<<"$out" || die "self-test: route/form group promote-hook/hook wrong"
  [[ $out != *'reject/none'* ]] || die "self-test: rejected candidates leaked into route/form grouping"

  # Top recurring open candidates: only recurrence>1, highest first, rejected
  # group excluded despite recurrence 2.
  section=$(sed -n '/^Top recurring open candidates:/,/^$/p' <<<"$out")
  [[ $section == *'captured 3 times'*'dupe-high'* ]] ||
    die "self-test: top-recurring missing recurrence-3 group (got: $section)"
  [[ $section == *'captured 2 times'*'dupe-low'* ]] ||
    die "self-test: top-recurring missing recurrence-2 group (got: $section)"
  [[ $section != *'dupe-rejected'* ]] ||
    die "self-test: top-recurring included a non-open recurring group"
  three_line=$(grep -n 'captured 3 times' <<<"$section" | head -1 | cut -d: -f1)
  two_line=$(grep -n 'captured 2 times' <<<"$section" | head -1 | cut -d: -f1)
  [[ $three_line -lt $two_line ]] ||
    die "self-test: top-recurring not sorted with highest recurrence first"

  # Expired open candidates: only status:open with expires < LEARNING_TODAY.
  section=$(sed -n '/^Expired open candidates:/,/^$/p' <<<"$out")
  [[ $section == *'c2-open-formB'* ]] || die "self-test: expired-open missing c2 (got: $section)"
  [[ $section == *'c4-open-recurring-a'* ]] || die "self-test: expired-open missing c4"
  [[ $section != *'c1-open-formA'* ]] || die "self-test: expired-open included a not-yet-expired candidate"
  [[ $section != *'c3-promoted'* ]] || die "self-test: expired-open included a non-open candidate"

  # Open candidate rows: exactly the status:open candidates (7), no others.
  section=$(sed -n '/^Open candidate rows:/,$p' <<<"$out")
  row_count=$(($(wc -l <<<"$section") - 2)) # minus header line and section title
  [[ $row_count -eq 7 ]] || die "self-test: expected 7 open candidate rows, got $row_count"
  [[ $section != *'c3-promoted'* ]] || die "self-test: open candidate rows included a promoted candidate"
  [[ $section != *'c9-rejected-recurring-a'* ]] || die "self-test: open candidate rows included a rejected candidate"

  printf 'review-candidates self-test passed\n'
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

review "${1:-.agents/learning}"
