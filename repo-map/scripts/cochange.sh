#!/usr/bin/env bash
# Show which tracked files have historically changed alongside a given path.
#
# Usage:
#   cochange.sh [--limit N] <path>
#   cochange.sh --self-test
set -euo pipefail

# Commits touching more files than this are treated as noise (mass
# reformats, renames, lockfile bumps) and excluded entirely -- both from the
# per-file counts and from the "total qualifying commits" denominator.
max_commit_files=40

usage() {
  printf 'usage: %s [--limit N] <path>\n' "$(basename "$0")" >&2
}

die() {
  printf 'cochange: %s\n' "$*" >&2
  exit 1
}

# Print "ratio\tcount\ttotal\tpath" rows (no header) for files that
# historically changed alongside $path in $repo_root's history, ranked by
# ratio desc, count desc, path asc, truncated to $limit. Parameterized by
# repo_root (rather than assuming the process cwd) so --self-test can drive
# it against a throwaway repo without touching the real one.
query_cochange() {
  local repo_root=$1 path=$2 limit=$3

  git -C "$repo_root" ls-files --error-unmatch -- "$path" >/dev/null 2>&1 ||
    die "not a tracked file: $path"

  # --follow (to survive renames) and --full-diff (to list every file in a
  # matching commit, not just $path) can't be combined in one `git log` call
  # ("--follow requires exactly one pathspec"), so this resolves the
  # qualifying commit hashes first, then asks `git diff-tree` for each
  # commit's full file list separately (no pathspec involved, so no
  # conflict). --root makes the very first commit in history diff against
  # the empty tree instead of being skipped as parentless.
  local hash
  {
    git -C "$repo_root" log --follow --no-merges --pretty=format:'%H' -- "$path" |
      while IFS= read -r hash || [ -n "$hash" ]; do
        printf '@@COMMIT@@%s\n' "$hash"
        git -C "$repo_root" diff-tree --no-commit-id --name-only -r --root "$hash"
      done
  } |
    awk -v target="$path" -v maxfiles="$max_commit_files" '
      function reset() {
        nfiles = 0
        delete file_seen
      }
      function flush_commit() {
        if (nfiles == 0 || nfiles > maxfiles || !(target in file_seen)) {
          reset()
          return
        }
        total++
        for (f in file_seen) {
          if (f != target) {
            count[f]++
          }
        }
        reset()
      }
      BEGIN { reset() }
      /^@@COMMIT@@/ { flush_commit(); next }
      NF == 0 { next }
      !($0 in file_seen) { file_seen[$0] = 1; nfiles++ }
      END {
        flush_commit()
        for (f in count) {
          if (count[f] < 2) continue
          printf "%.2f\t%d\t%d\t%s\n", count[f] / total, count[f], total, f
        }
      }
    ' |
    sort -t "$(printf '\t')" -k1,1rn -k2,2rn -k4,4 |
    head -n "$limit"
}

self_test() {
  local tmp out rc
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN

  (
    cd "$tmp"
    git init -q
    git config user.email test@example.com
    git config user.name test

    printf 'a\n' >a.txt
    printf 'b\n' >b.txt
    printf 'c\n' >c.txt
    git add a.txt b.txt c.txt
    git commit -q -m init

    for i in 1 2 3 4; do
      printf 'a%d\n' "$i" >>a.txt
      printf 'b%d\n' "$i" >>b.txt
      git add a.txt b.txt
      git commit -q -m "couple $i"
    done

    printf 'alone\n' >>a.txt
    git add a.txt
    git commit -q -m alone

    printf 'c-change\n' >>c.txt
    git add c.txt
    git commit -q -m "c alone"

    for i in $(seq 1 50); do
      printf 'x%d\n' "$i" >"big-$i.txt"
    done
    printf 'big-change\n' >>a.txt
    git add -A
    git commit -q -m huge
  )

  # Case 1: a.txt and b.txt co-changed in 5 of a.txt's 6 qualifying commits
  # (init + 4 "couple" commits; the oversized "huge" commit is excluded from
  # both the count and the total). c.txt only co-changed once (init) and is
  # dropped by the count<2 floor. The oversized commit's fan-out files never
  # appear at all.
  out=$(query_cochange "$tmp" a.txt 10)
  [[ $(wc -l <<<"$out") -eq 1 ]] ||
    die "self-test: expected exactly one row for a.txt (got: $out)"
  [[ $out == $'0.83\t5\t6\tb.txt' ]] ||
    die "self-test: expected b.txt at ratio 0.83 (got: $out)"
  [[ $out != *c.txt* ]] || die "self-test: c.txt should be dropped (count<2)"
  [[ $out != *big-* ]] || die "self-test: oversized commit's files leaked through"

  # Case 2: c.txt's own co-changes (a.txt, b.txt from the init commit) are
  # each below the count<2 floor -> header-only output, exit 0.
  out=$(query_cochange "$tmp" c.txt 10) && rc=0 || rc=$?
  [[ $rc -eq 0 ]] || die "self-test: sub-threshold query should exit 0 (rc=$rc)"
  [[ -z $out ]] || die "self-test: sub-threshold query should print nothing (got: $out)"

  # Case 3: untracked path -> exit 1 via die().
  (query_cochange "$tmp" nonexistent.txt 10 >/dev/null 2>&1) && rc=0 || rc=$?
  [[ $rc -ne 0 ]] || die "self-test: untracked path should fail"

  # Case 4: no arguments at all -> the script's usage/exit-2 behavior.
  "$0" >/dev/null 2>&1 && rc=0 || rc=$?
  [[ $rc -eq 2 ]] || die "self-test: no-args invocation should exit 2 (rc=$rc)"

  printf 'cochange.sh self-test passed\n'
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

limit=${REPO_MAP_COCHANGE_LIMIT:-10}
if [ "${1:-}" = "--limit" ]; then
  [ "$#" -ge 3 ] || {
    usage
    exit 2
  }
  limit=$2
  shift 2
fi

if [ "$#" -eq 0 ]; then
  usage
  exit 2
fi

case "$limit" in
'' | *[!0-9]*)
  printf 'limit must be a positive integer\n' >&2
  exit 2
  ;;
esac

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

{
  printf 'ratio\tcount\ttotal\tpath\n'
  query_cochange "$repo_root" "$1" "$limit"
}
