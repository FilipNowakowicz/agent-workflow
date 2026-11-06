#!/usr/bin/env bash
# Reviewer entrypoint for the agent issue-to-PR loop (v2 closed loop).
#
# Reviews a PR's diff against its linked issue and emits a structured decision
# as a reviewer-evidence JSON file (schema agent-reviewer-evidence/v1, #227),
# then hands that evidence to agent-merge-gate (control-plane script;
# scripts/agent-merge-gate in this provider checkout, .agents/scripts/
# agent-merge-gate in an installed consumer repo), which applies the risk
# gate: low-risk + approved PRs can have GitHub native, CI-gated auto-merge
# enabled, while everything else is left for a human.
#
# Two modes:
#   review (default)  Scaffold evidence from the issue's acceptance criteria,
#                     run a reviewer model (`claude -p`) to fill it from the PR
#                     diff + issue, validate it via agent-review-stage, post a
#                     summary comment, and run the merge gate.
#   --decision-only   Skip the model: take an already-filled --evidence file,
#                     (optionally) post it, and run the merge gate. Offline-
#                     friendly with --files-from; used by the self-test.
#
# SAFETY: this never merges directly, never pushes to a base branch, and never
# uses `gh pr merge --admin`. Merge authority is GitHub native auto-merge gated
# by `merge-gate` (enabled only with --enable-auto-merge on an "auto" decision).
#
# TRUST: the merge gate and the review stage are run from the committed
# `.agents` tree at the trusted base ref (git archive of origin/main, else
# main; or $AGENT_GATE_TRUSTED_ROOT), never from the working tree, which may be
# the PR under review and so could replace the gate that decides it.
# --enable-auto-merge is refused when no trusted base can be established.
# Not covered: this wrapper script itself. Run it from a checkout of the base
# branch, not from the PR's tree (a PR that replaces the wrapper can replace
# any check the wrapper does).
set -euo pipefail

AGENT_CLAUDE_CMD="${AGENT_CLAUDE_CMD:-claude}"
AGENT_REVIEW_MODEL="${AGENT_REVIEW_MODEL:-}"

usage() {
  cat <<'EOF'
Usage: agent-review-pr.sh --pr <n> [--issue <n>] [--enable-auto-merge]
                          [--no-comment] [--out <path>]
       agent-review-pr.sh --decision-only --evidence <path>
                          (--pr <n> | --files-from <path>) [--enable-auto-merge]
       agent-review-pr.sh --self-test

Review a PR against its linked issue, emit reviewer evidence, and run the
risk-gated merge gate.

Options:
  --pr <n>             PR number to review.
  --issue <n>          Linked issue number. Default: discovered from the PR's
                       closing references / body.
  --evidence <path>    review mode: output path for the evidence JSON
                       (default: state/review/issue-<i>-pr-<n>.json, or
                       .agents/state/review/... in an installed consumer
                       repo that has a top-level .agents/ directory).
                       --decision-only: the pre-filled evidence file to use.
  --decision-only      Skip the reviewer model; use an existing --evidence file
                       and run the merge gate only.
  --files-from <path>  --decision-only: changed-paths source forwarded to the
                       merge gate ("-" for stdin). Offline; never calls GitHub.
  --enable-auto-merge  On an "auto" gate decision, enable GitHub native auto-
                       merge (still gated by merge-gate). Default: dry-run.
  --base-ref <ref>     Git ref whose committed `.agents` tree supplies the gate
                       and review stage (default: origin/main, else main).
  --no-comment         Do not post the review summary as a PR comment.
  --out <path>         Alias for --evidence in review mode.
  --self-test          Run a deterministic, offline self-test and exit.
  -h, --help           Show this help.

Environment:
  AGENT_CLAUDE_CMD     Claude CLI command (default: claude).
  AGENT_REVIEW_MODEL   Optional model override passed to the reviewer session.
EOF
}

die() {
  printf 'agent-review-pr: %s\n' "$*" >&2
  exit 2
}

script_dir() {
  CDPATH='' cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

repo_root() {
  CDPATH='' cd -- "$(script_dir)/.." && pwd
}

# A consumer repo installs orchestration entrypoints at repo-root
# scripts/agent-*.sh and the rest of the control plane under .agents/
# (see docs/provider-consumer-layout.md), while this provider repo keeps
# orchestration/, scripts/, and state/ as plain siblings at the repo root.
# The presence of a top-level .agents/ directory distinguishes the two.
control_plane_prefix() {
  [[ -d "$(repo_root)/.agents" ]] && printf '.agents/\n' || printf '\n'
}

# TRUSTED_ROOT is the `.agents` directory the gate and review stage are run
# from; TRUSTED is 1 when it came from reviewed code (an explicit
# $AGENT_GATE_TRUSTED_ROOT, or the committed `.agents` tree at the base ref),
# 0 when it fell back to the working tree.
TRUSTED_ROOT=""
TRUSTED=0
BASE_REF=""

resolve_trusted_root() {
  local tmp="$1" repo ref
  TRUSTED=0
  if [[ -n ${AGENT_GATE_TRUSTED_ROOT:-} ]]; then
    [[ -d $AGENT_GATE_TRUSTED_ROOT ]] ||
      die "AGENT_GATE_TRUSTED_ROOT is not a directory: $AGENT_GATE_TRUSTED_ROOT"
    TRUSTED_ROOT="$AGENT_GATE_TRUSTED_ROOT"
    TRUSTED=1
    return 0
  fi
  if repo=$(git -C "$(repo_root)" rev-parse --show-toplevel 2>/dev/null); then
    for ref in ${BASE_REF:+"$BASE_REF"} origin/main main; do
      git -C "$repo" rev-parse --verify --quiet "$ref^{commit}" >/dev/null 2>&1 || continue
      mkdir -p "$tmp/trusted"
      if git -C "$repo" archive "$ref" .agents 2>/dev/null | tar -x -C "$tmp/trusted" 2>/dev/null &&
        [[ -x "$tmp/trusted/.agents/scripts/agent-merge-gate" ]]; then
        TRUSTED_ROOT="$tmp/trusted/.agents"
        TRUSTED=1
        return 0
      fi
      break
    done
  fi
  TRUSTED_ROOT="$(repo_root)/$(control_plane_prefix)"
  TRUSTED_ROOT="${TRUSTED_ROOT%/}"
}

review_stage_bin() {
  printf '%s/scripts/agent-review-stage\n' "$TRUSTED_ROOT"
}

merge_gate_bin() {
  printf '%s/scripts/agent-merge-gate\n' "$TRUSTED_ROOT"
}

review_state_dir() {
  printf '%sstate/review\n' "$(control_plane_prefix)"
}

# Best-effort discovery of the issue a PR closes: prefer GitHub's structured
# closingIssuesReferences, fall back to a closing keyword in the PR body.
discover_linked_issue() {
  local pr="$1" issue
  issue=$(gh pr view "$pr" --json closingIssuesReferences \
    --jq '.closingIssuesReferences[0].number // empty' 2>/dev/null || true)
  if [[ -z $issue ]]; then
    issue=$(gh pr view "$pr" --json body --jq '.body // ""' 2>/dev/null |
      grep -oiE '(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+#[0-9]+' |
      grep -oE '[0-9]+' | head -n1 || true)
  fi
  printf '%s' "$issue"
}

build_review_prompt() {
  local pr="$1" issue="$2" evidence="$3" stage_bin="$4"
  cat <<EOF
You are the reviewer stage of an autonomous issue-to-PR loop. Review pull
request #${pr} against its linked issue #${issue} and emit a structured
decision. Do NOT merge the PR, do NOT push to any branch, and do NOT edit
repository files other than the evidence file named below.

Steps:
1. Read the issue with: gh issue view ${issue} --json title,body
2. Read the PR metadata and diff with: gh pr view ${pr} ; gh pr diff ${pr}
3. Judge whether the diff satisfies every "## Acceptance criteria" bullet,
   whether validation evidence is credible, and whether any changed path is
   security/deploy/host-state sensitive.
4. Overwrite ${evidence} with a schema-valid agent-reviewer-evidence/v1 JSON:
   - result: "approved" only if every acceptance criterion is met with concrete
     evidence and no protected path is touched; "changes_requested" if fixable
     gaps remain; "blocked" if you cannot evaluate it.
   - acceptance_criteria[]: one entry per issue criterion, each with concrete
     evidence (what in the diff satisfies it), not a placeholder.
   - validation_commands[]: the checks the PR ran and their results.
   - residual_risk: the honest residual risk if this merged.
5. Validate your file with:
   ${stage_bin} check ${evidence} --issue ${issue}
   Fix it until that check passes.

Merge authority is decided downstream by agent-merge-gate; your only job is an
honest, schema-valid decision. Keep output terse: do not paste full diffs or
build logs into the conversation.
EOF
}

post_pr_comment() {
  local pr="$1" evidence="$2"
  command -v gh >/dev/null 2>&1 || return 0
  local result tmp
  result=$(jq -r '.result' "$evidence" 2>/dev/null || printf 'unknown')
  tmp=$(mktemp)
  # shellcheck disable=SC2016  # literal backticks render `code` in the Markdown comment
  {
    printf '## Agent reviewer decision: `%s`\n\n' "$result"
    printf 'Automated reviewer-stage evidence (advisory; `merge-gate` remains the gate).\n\n'
    printf '**Residual risk:** %s\n\n' "$(jq -r '.residual_risk // "n/a"' "$evidence")"
    printf '| Acceptance criterion | Evidence |\n| --- | --- |\n'
    jq -r '.acceptance_criteria[]? | "| " + (.criterion | gsub("\\|";"\\\\|")) + " | " + (.evidence | gsub("\\|";"\\\\|")) + " |"' "$evidence"
  } >"$tmp"
  if gh pr comment "$pr" --body-file "$tmp" >/dev/null 2>&1; then
    echo "agent-review-pr: posted reviewer decision comment to PR #$pr" >&2
  else
    echo "agent-review-pr: failed to post reviewer comment to PR #$pr" >&2
  fi
  rm -f "$tmp"
}

run_gate() {
  local pr="$1" evidence="$2" enable="$3" files_from="$4" json="$5"
  local gate
  gate="$(merge_gate_bin)"
  [[ -x $gate ]] || die "agent-merge-gate not found or not executable: $gate"
  local -a args=(--evidence "$evidence")
  if [[ -n $files_from ]]; then
    args+=(--files-from "$files_from")
  else
    args+=(--pr "$pr")
  fi
  [[ $enable -eq 1 ]] && args+=(--enable)
  [[ $json -eq 1 ]] && args+=(--json)
  # Pin the gate's own helper root to the same trusted tree it was loaded from.
  if [[ $TRUSTED -eq 1 ]]; then
    AGENT_GATE_TRUSTED_ROOT="$TRUSTED_ROOT" "$gate" "${args[@]}"
  else
    "$gate" "${args[@]}"
  fi
}

run() {
  local pr="" issue="" evidence="" decision_only=0 enable=0 comment=1 files_from="" json=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --pr)
      pr="${2:?--pr needs a value}"
      [[ $pr =~ ^[0-9]+$ ]] || die "--pr must be a positive integer"
      shift 2
      ;;
    --issue)
      issue="${2:?--issue needs a value}"
      [[ $issue =~ ^[0-9]+$ ]] || die "--issue must be a positive integer"
      shift 2
      ;;
    --evidence | --out)
      evidence="${2:?--evidence needs a value}"
      shift 2
      ;;
    --files-from)
      files_from="${2:?--files-from needs a value}"
      shift 2
      ;;
    --decision-only)
      decision_only=1
      shift
      ;;
    --enable-auto-merge)
      enable=1
      shift
      ;;
    --base-ref)
      BASE_REF="${2:?--base-ref needs a value}"
      shift 2
      ;;
    --no-comment)
      comment=0
      shift
      ;;
    --json)
      json=1
      shift
      ;;
    *)
      die "unknown argument: $1"
      ;;
    esac
  done

  command -v jq >/dev/null 2>&1 || die "jq not found"

  local trust_tmp
  trust_tmp=$(mktemp -d)
  trap 'rm -rf "${trust_tmp:-}"' EXIT
  resolve_trusted_root "$trust_tmp"
  if [[ $TRUSTED -ne 1 ]]; then
    [[ $enable -eq 1 ]] &&
      die "refusing --enable-auto-merge: no trusted base for the merge gate (set AGENT_GATE_TRUSTED_ROOT, or run inside a repo whose origin/main or main commits .agents/). A PR must not run its own gate."
    echo "agent-review-pr: WARNING: no trusted base ref; gate runs from the working tree (dry-run only)" >&2
  fi

  if [[ $decision_only -eq 1 ]]; then
    [[ -n $evidence ]] || die "--decision-only requires --evidence"
    [[ -f $evidence ]] || die "evidence file not found: $evidence"
    [[ -n $pr || -n $files_from ]] || die "--decision-only requires --pr or --files-from"
    [[ $comment -eq 1 && -n $pr && -z $files_from ]] && post_pr_comment "$pr" "$evidence"
    run_gate "$pr" "$evidence" "$enable" "$files_from" "$json"
    return $?
  fi

  # Review mode: needs GitHub + a model.
  [[ -n $pr ]] || die "--pr is required (see --help)"
  command -v gh >/dev/null 2>&1 || die "gh not found"
  command -v "$AGENT_CLAUDE_CMD" >/dev/null 2>&1 || die "$AGENT_CLAUDE_CMD CLI not found"

  if [[ -z $issue ]]; then
    issue=$(discover_linked_issue "$pr")
    [[ -n $issue ]] || die "could not discover a linked issue for PR #$pr; pass --issue"
    echo "agent-review-pr: PR #$pr linked to issue #$issue" >&2
  fi

  local stage
  stage="$(review_stage_bin)"
  [[ -x $stage ]] || die "agent-review-stage not found or not executable: $stage"

  evidence="${evidence:-$(review_state_dir)/issue-${issue}-pr-${pr}.json}"
  mkdir -p "$(dirname "$evidence")"
  "$stage" init --issue "$issue" --pr "$pr" --out "$evidence" >/dev/null ||
    die "failed to scaffold reviewer evidence for issue #$issue / PR #$pr"
  echo "agent-review-pr: scaffolded evidence at $evidence" >&2

  local prompt
  prompt=$(build_review_prompt "$pr" "$issue" "$evidence" "bash $stage")
  local -a claude_args=(-p "$prompt" --output-format stream-json --verbose)
  [[ -n $AGENT_REVIEW_MODEL ]] && claude_args+=(--model "$AGENT_REVIEW_MODEL")
  echo "agent-review-pr: running reviewer session for PR #$pr ..." >&2
  "$AGENT_CLAUDE_CMD" "${claude_args[@]}" || die "reviewer session failed; inspect $evidence"

  "$stage" check "$evidence" --issue "$issue" ||
    die "reviewer evidence failed validation; not gating PR #$pr"

  [[ $comment -eq 1 ]] && post_pr_comment "$pr" "$evidence"
  run_gate "$pr" "$evidence" "$enable" "" "$json"
}

self_test() {
  local tmp script_path out
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  script_path="$(script_dir)/$(basename "${BASH_SOURCE[0]}")"

  # Safety invariant: no actual `gh pr merge` command anywhere in this script.
  if grep -nE '^[[:space:]]*gh +pr +merge' "$script_path"; then
    die "self-test: this script must not run 'gh pr merge' directly (merge authority is agent-merge-gate)"
  fi

  local approved="$tmp/approved.json" changes="$tmp/changes.json"
  cat >"$approved" <<'EOF'
{
  "schema": "agent-reviewer-evidence/v1",
  "issue": 284,
  "pr": 9001,
  "result": "approved",
  "acceptance_criteria": [
    {"criterion": "low-risk change", "evidence": "docs only"}
  ],
  "validation_commands": [
    {"command": "bash scripts/validate.sh docs", "result": "passed"}
  ],
  "residual_risk": "Docs-only; CI gate still required."
}
EOF
  jq '.result = "changes_requested"' "$approved" >"$changes"

  local low="$tmp/low.txt" high="$tmp/high.txt"
  printf 'docs/architecture.md\n' >"$low"
  printf '.sops.yaml\n' >"$high"

  # decision-only, low-risk + approved -> gate decides auto (dry-run, offline).
  out=$("$script_path" --decision-only --evidence "$approved" --files-from "$low" --json)
  jq -e '.decision == "auto"' <<<"$out" >/dev/null ||
    die "self-test: expected low-risk+approved decision-only to be auto (got: $out)"

  # decision-only, high-risk path -> human.
  out=$("$script_path" --decision-only --evidence "$approved" --files-from "$high" --json)
  jq -e '.decision == "human"' <<<"$out" >/dev/null ||
    die "self-test: expected high-risk decision-only to be human (got: $out)"

  # decision-only, changes_requested evidence -> human.
  out=$("$script_path" --decision-only --evidence "$changes" --files-from "$low" --json)
  jq -e '.decision == "human"' <<<"$out" >/dev/null ||
    die "self-test: expected changes_requested decision-only to be human (got: $out)"

  # H2 regression: a PR that replaces the working-tree gate must not decide
  # itself. Consumer-shaped fixture: committed .agents is the trusted base,
  # the working tree is tampered, and the wrapper must still say "human".
  local root c
  root="$(repo_root)"
  c="$tmp/consumer"
  mkdir -p "$c/.agents" "$c/scripts"
  cp -r "$root/scripts" "$c/.agents/scripts"
  cp "$root/governance.yaml" "$root/model-routing.yaml" "$root/capability-profiles.yaml" "$c/.agents/"
  cp "$script_path" "$c/scripts/agent-review-pr.sh"
  git -C "$c" init -q -b main
  git -C "$c" config user.email test@example.invalid
  git -C "$c" config user.name test
  git -C "$c" add -A -f
  git -C "$c" commit -qm base
  git -C "$c" update-ref refs/remotes/origin/main HEAD
  printf '#!/usr/bin/env bash\necho %s\n' "'{\"decision\":\"auto\"}'" >"$c/.agents/scripts/agent-merge-gate"
  out=$(cd "$c" && ./scripts/agent-review-pr.sh --decision-only --no-comment --evidence "$approved" \
    --files-from "$high" --json 2>/dev/null)
  jq -e '.decision == "human"' <<<"$out" >/dev/null ||
    die "self-test: a tampered working-tree gate decided its own PR (got: $out)"
  # ... and --enable-auto-merge is refused outright when no trusted base exists.
  git -C "$c" update-ref -d refs/remotes/origin/main
  git -C "$c" branch -q -m main trunk
  if (cd "$c" && ./scripts/agent-review-pr.sh --decision-only --no-comment --evidence "$approved" \
    --pr 9001 --enable-auto-merge) >/dev/null 2>&1; then
    die "self-test: --enable-auto-merge without a trusted base must be refused"
  fi

  # --decision-only without --evidence is rejected.
  if "$script_path" --decision-only --files-from "$low" >/dev/null 2>&1; then
    die "self-test: expected --decision-only without --evidence to fail"
  fi

  printf 'agent-review-pr self-test passed\n'
}

main() {
  case "${1:-}" in
  --self-test)
    self_test
    exit 0
    ;;
  -h | --help | "")
    usage
    [[ ${1:-} == "" ]] && exit 2
    exit 0
    ;;
  *)
    run "$@"
    ;;
  esac
}

main "$@"
