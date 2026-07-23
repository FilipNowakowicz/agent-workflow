#!/usr/bin/env bash
# Heuristic: has a candidate's evidence already landed?
#
# Reviewers re-derived this by hand — git-archaeology each implement-fix
# candidate to see whether the fix was already merged before promoting it. This
# automates the cheap signals: commit SHAs in `evidence` that are ancestors of
# HEAD, and PR numbers that GitHub reports as merged. It advises only; the
# reviewer still decides (promote / superseded / reject). It never edits files.
#
# This repo squash-merges, so a pre-merge commit SHA is NOT an ancestor of main
# after its PR lands — a merged PR is the more reliable signal. But only the PR
# named in the candidate's `fix-pr` field counts as the landing PR: a #NNN that
# merely appears in the evidence prose may be related/contrasting context, so it
# is reported but never on its own marks the candidate resolved (issue #14).
# Evidence that cites neither a SHA nor a merged fix-pr yields NO SIGNAL: that is
# a capture gap, not a clean bill of health, and still needs manual judgement.
#
# Usage:
#   check-candidate-liveness.sh            # open candidates (the actionable set)
#   check-candidate-liveness.sh all        # every candidate regardless of status
#   check-candidate-liveness.sh <substr>   # candidates whose id/path matches substr
#   check-candidate-liveness.sh --self-test
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$script_dir/.." && pwd)

usage() {
  cat <<'EOF'
Usage:
  check-candidate-liveness.sh            # open candidates (the actionable set)
  check-candidate-liveness.sh all        # every candidate regardless of status
  check-candidate-liveness.sh <substr>   # candidates whose id/path matches substr
  check-candidate-liveness.sh --self-test
EOF
}

die() {
  printf 'check-candidate-liveness: %s\n' "$*" >&2
  exit 1
}

# Read a single-line metadata field straight from a candidate file (same
# contract as index-candidates.sh's field_from_path): first match, tabs->space,
# strip surrounding quotes. Used for fields the TSV index does not surface as
# columns, such as `fix-pr`.
field_from_path() {
  local path=$1
  local name=$2
  sed -n "s/^${name}:[[:space:]]*//p" "$path" | head -1 |
    tr '\t' ' ' |
    sed "s/^\"//; s/\"$//; s/^'//; s/'$//"
}

# Emit the liveness report for candidates under $root/candidates, filtered by
# $filter, treating gh as available iff $have_gh = 1. Parameterized (rather
# than reading the global root/have_gh) so --self-test can drive it against a
# throwaway repo without touching real learning/candidates or calling gh.
report() {
  local root=$1
  local filter=$2
  local have_gh=$3
  local tmp
  tmp=${TMPDIR:-/tmp}/learning-liveness-$$.tsv
  trap 'rm -f "$tmp"' RETURN

  "$script_dir/index-candidates.sh" "$root" >"$tmp"

  printf 'Candidate liveness (heuristic — verify before acting)\n'
  [ "$have_gh" -eq 1 ] || printf '(gh unavailable: PR merge state not checked)\n'
  printf '\n'

  # Columns from index-candidates.sh (12 tab-separated fields):
  # 1 path 2 id 3 status 4 expires 5 type 6 route 7 best_form
  # 8 dedupe_key 9 triggers 10 targets 11 evidence 12 recurrence
  #
  # Extract by explicit column number with cut rather than `IFS=$'\t' read`:
  # a single tab is IFS-whitespace, so read collapses any empty middle column
  # (every field except evidence is optional) and silently shifts evidence /
  # recurrence into the wrong variable. cut keeps empty fields, so adding the
  # trailing recurrence column to the schema cannot misalign the reader (#8).
  tail -n +2 "$tmp" | while IFS= read -r row; do
    local path id status route best_form targets evidence
    path=$(printf '%s' "$row" | cut -f1)
    id=$(printf '%s' "$row" | cut -f2)
    status=$(printf '%s' "$row" | cut -f3)
    route=$(printf '%s' "$row" | cut -f6)
    best_form=$(printf '%s' "$row" | cut -f7)
    targets=$(printf '%s' "$row" | cut -f10)
    evidence=$(printf '%s' "$row" | cut -f11)

    case "$filter" in
    __open__) [ "$status" = "open" ] || continue ;;
    all) ;;
    *) case "$id$path" in *"$filter"*) ;; *) continue ;; esac ;;
    esac

    # Only the PR explicitly tagged as the fix (the `fix-pr` field) can mark a
    # candidate resolved; PRs that merely appear in the evidence prose are
    # contextual and are reported but never flip the verdict (issue #14).
    local fix_pr
    fix_pr=$(field_from_path "$path" fix-pr | grep -oE '[0-9]+' | head -1 || true)

    local signals resolved saw_context_pr
    signals=""
    resolved=0
    saw_context_pr=0

    # Commit SHAs: validate each hex token is a real commit (filters sha256
    # hashes and store paths), then test ancestry against HEAD.
    for sha in $(printf '%s\n' "$evidence" | grep -oE '\b[0-9a-f]{7,40}\b' | sort -u); do
      git -C "$root" rev-parse --verify --quiet "${sha}^{commit}" >/dev/null 2>&1 || continue
      if git -C "$root" merge-base --is-ancestor "$sha" HEAD 2>/dev/null; then
        signals+="    commit ${sha} -> ancestor of HEAD (landed)\n"
        resolved=1
      else
        signals+="    commit ${sha} -> known commit, NOT on HEAD\n"
      fi
    done

    # PR references (#NNN). Only meaningful with gh. Evidence PRs are reported for
    # context; only the tagged fix-pr's MERGED state marks the candidate resolved.
    if [ "$have_gh" -eq 1 ]; then
      local fix_pr_seen state
      fix_pr_seen=0
      for pr in $(printf '%s\n' "$evidence" | grep -oE '#[0-9]+' | tr -d '#' | sort -u); do
        state=$(gh pr view "$pr" --json state --jq .state 2>/dev/null || true)
        [ -n "$state" ] || continue
        if [ -n "$fix_pr" ] && [ "$pr" = "$fix_pr" ]; then
          signals+="    PR #${pr} -> ${state} (fix-pr)\n"
          fix_pr_seen=1
          [ "$state" = "MERGED" ] && resolved=1
        else
          signals+="    PR #${pr} -> ${state} (context)\n"
          saw_context_pr=1
        fi
      done
      # A fix-pr need not appear in the evidence prose; query it directly too.
      if [ -n "$fix_pr" ] && [ "$fix_pr_seen" -eq 0 ]; then
        state=$(gh pr view "$fix_pr" --json state --jq .state 2>/dev/null || true)
        if [ -n "$state" ]; then
          signals+="    PR #${fix_pr} -> ${state} (fix-pr)\n"
          [ "$state" = "MERGED" ] && resolved=1
        fi
      fi
    fi

    local verdict
    if [ "$resolved" -eq 1 ]; then
      verdict="LIKELY RESOLVED — consider 'superseded'; do not re-implement"
    elif [ -n "$fix_pr" ]; then
      verdict="UNRESOLVED — tagged fix-pr #${fix_pr} not observed merged"
    elif [ "$saw_context_pr" -eq 1 ]; then
      verdict="UNVERIFIED — evidence cites PR(s) as context only; tag the landing PR with a 'fix-pr:' field to confirm resolution"
    elif [ -n "$signals" ]; then
      verdict="UNRESOLVED — evidence pointers exist but none have landed"
    else
      verdict="NO SIGNAL — no commit/fix-pr pointer; judge from evidence + targets"
    fi

    printf '%s  [%s/%s]  status=%s\n' "$id" "$route" "$best_form" "$status"
    [ -n "$signals" ] && printf '%b' "$signals"
    printf '  verdict: %s\n' "$verdict"
    [ -n "$targets" ] && printf '  targets: %s\n' "$targets"
    printf '\n'
  done
}

# Print the report's block for a single candidate id (its header line up to
# the next blank line), so assertions can target one candidate without a
# substring match colliding with another candidate's id.
block_for() {
  local id=$1
  local out=$2
  awk -v id="$id" '
    $0 ~ ("^" id "[[:space:]]") { p = 1 }
    p { print }
    p && /^$/ { exit }
  ' <<<"$out"
}

self_test() {
  local tmp out base_branch ancestor_sha not_ancestor_sha
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN

  git -C "$tmp" init -q
  git -C "$tmp" config user.email test@example.com
  git -C "$tmp" config user.name test

  printf 'seed\n' >"$tmp/seed.txt"
  git -C "$tmp" -c commit.gpgsign=false add seed.txt
  git -C "$tmp" -c commit.gpgsign=false commit -q -m seed
  base_branch=$(git -C "$tmp" symbolic-ref --short HEAD)
  ancestor_sha=$(git -C "$tmp" rev-parse HEAD)

  # A commit that exists in the object database (kept alive by the "other"
  # branch ref) but is not reachable from HEAD on base_branch: a known,
  # not-landed commit.
  git -C "$tmp" checkout -q -b other
  printf 'other\n' >"$tmp/other.txt"
  git -C "$tmp" -c commit.gpgsign=false add other.txt
  git -C "$tmp" -c commit.gpgsign=false commit -q -m other
  not_ancestor_sha=$(git -C "$tmp" rev-parse HEAD)

  git -C "$tmp" checkout -q "$base_branch"
  printf 'more\n' >"$tmp/more.txt"
  git -C "$tmp" -c commit.gpgsign=false add more.txt
  git -C "$tmp" -c commit.gpgsign=false commit -q -m more

  mkdir -p "$tmp/candidates"

  cat >"$tmp/candidates/ancestor.yml" <<EOF
id: candidate-ancestor
status: open
route: implement-fix
best_form: test
evidence: landed in commit ${ancestor_sha}
targets: some/file.sh
EOF

  cat >"$tmp/candidates/known-not-landed.yml" <<EOF
id: candidate-known-not-landed
status: open
route: implement-fix
best_form: test
evidence: proposed fix in commit ${not_ancestor_sha}
targets: some/other.sh
EOF

  cat >"$tmp/candidates/no-pointer.yml" <<'EOF'
id: candidate-no-pointer
status: open
route: implement-fix
best_form: test
evidence: no commit or PR pointer here, just prose
targets: some/thing.sh
EOF

  cat >"$tmp/candidates/promoted-status.yml" <<'EOF'
id: candidate-promoted-status
status: promoted
route: implement-fix
best_form: test
evidence: no commit or PR pointer here either
targets: some/thing-else.sh
EOF

  # Default filter (__open__): only status=open candidates, gh-dependent PR
  # checks skipped entirely (have_gh=0) so this needs no network access.
  out=$(report "$tmp" __open__ 0)

  grep -Fq 'gh unavailable' <<<"$out" ||
    die "default report did not note gh unavailable"

  grep -Fq 'LIKELY RESOLVED' <<<"$(block_for candidate-ancestor "$out")" ||
    die "ancestor commit should verdict LIKELY RESOLVED"

  grep -Fq 'UNRESOLVED' <<<"$(block_for candidate-known-not-landed "$out")" ||
    die "known-but-not-landed commit should verdict UNRESOLVED"

  grep -Fq 'NO SIGNAL' <<<"$(block_for candidate-no-pointer "$out")" ||
    die "candidate with no commit/PR pointer should verdict NO SIGNAL"

  [[ $out != *candidate-promoted-status* ]] ||
    die "default __open__ filter should exclude non-open status"

  # 'all' filter: every status, including non-open.
  out=$(report "$tmp" all 0)
  grep -Fq 'candidate-promoted-status' <<<"$out" ||
    die "'all' filter should include non-open candidates"

  # Substring filter: matches by id/path, excludes everything else.
  out=$(report "$tmp" known-not-landed 0)
  grep -Fq 'candidate-known-not-landed' <<<"$out" ||
    die "substring filter should include the matching candidate"
  [[ $out != *candidate-ancestor* ]] ||
    die "substring filter should exclude non-matching candidates"
  [[ $out != *candidate-no-pointer* ]] ||
    die "substring filter should exclude non-matching candidates"

  printf 'check-candidate-liveness self-test passed\n'
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

have_gh=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  have_gh=1
fi

filter=${1:-__open__}
report "$root" "$filter" "$have_gh"
