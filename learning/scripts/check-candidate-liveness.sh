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
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$script_dir/.." && pwd)

filter=${1:-__open__}
tmp=${TMPDIR:-/tmp}/learning-liveness-$$.tsv
trap 'rm -f "$tmp"' EXIT

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

"$script_dir/index-candidates.sh" "$root" >"$tmp"

have_gh=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  have_gh=1
fi

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
  fix_pr=$(field_from_path "$path" fix-pr | grep -oE '[0-9]+' | head -1 || true)

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
