# The Self-Hosted Issue Loop

`orchestration/agent-session.sh`, `orchestration/agent-run-issue.sh`, and
`orchestration/agent-review-pr.sh` together implement a self-hosted issue
loop: an operator starts a disposable VM, the VM dispatches a headless Claude
session at one issue, the session pushes a branch and opens a PR, and an
(optional) automated reviewer stage evaluates it before a human merges. It
was extracted from a real dogfood deployment on Google Cloud over Tailscale
("gcp-agent" in the original deployment); the architecture is generic, but
every default value below describes that original setup, not a requirement.

## Architecture

```text
operator workstation                 agent host (VM, normally powered off)
─────────────────────                ─────────────────────────────────────
agent-session.sh
  starts the VM, waits for SSH   ──▶  powers on
  preflights gh + claude auth    ──▶  preflight probes (gh auth status,
  ships its copy of                   a cheap "say ok" claude call)
  agent-run-issue.sh             ──▶  agent-run-issue.sh
  runs the issue loop via SSH         bootstraps/syncs AGENT_REPO_DIR,
                                       runs claude -p headless per issue,
                                       pushes a branch, opens a PR
  collects logs/artifacts back   ◀──  writes outcome + session-log files
  the VM idles back off               under AGENT_OUTCOME_DIR/AGENT_SESSION_DIR

(separately, on any host)
agent-review-pr.sh
  reviews a PR against its linked issue, emits reviewer-evidence JSON,
  and runs agent-merge-gate — never merges or pushes itself
```

## Prerequisites

- A VM (or any always-or-on-demand host) reachable over SSH, with `gh` and
  a Claude Code CLI (`claude` by default) installed and authenticated.
- `gh auth status` must succeed non-interactively on that host (a scoped
  PAT via `gh`'s credential helper, not an interactive login).
- The Claude CLI must be authenticated and have quota; both scripts
  preflight this with a cheap `claude -p "say ok"` probe before starting
  any billed session.
- If the host is started/stopped by `agent-session.sh`, it currently
  assumes `gcloud compute instances start/stop` and Tailscale for
  reachability (`AGENT_FQDN`). A host that is always-on, or managed by a
  different cloud provider, can skip `agent-session.sh` and invoke
  `agent-run-issue.sh` directly on the host.

## Configuration

Every host-specific or repo-specific value is an environment variable with
a documented default; see each script's own header comment (`--help` or
`grep '^#'`) for the full list. The ones that matter most when adapting
this to a different repo or host:

- `agent-session.sh`: `AGENT_NAME`, `AGENT_ZONE`, `AGENT_FQDN`, `SSH_USER`,
  `REMOTE_AGENT_REPO_DIR`.
- `agent-run-issue.sh`: `AGENT_REPO_DIR`, `REPO_URL` (required if
  `AGENT_REPO_DIR` is not already a clone — there is no baked-in default
  repo), `BASE_BRANCH`, `AGENT_VERIFICATION_GUIDANCE` (how the dispatched
  session should validate its change — set this to your repo's actual
  test/build/verification command), `AGENT_RUNNER_LABEL`.
- `agent-review-pr.sh`: `AGENT_CLAUDE_CMD`, `AGENT_REVIEW_MODEL`.

## Trust boundary

This loop opens PRs; it never merges and never pushes to the base branch.
Concretely:

- `agent-run-issue.sh`'s dispatch prompt explicitly instructs the inner
  session not to merge or push to `BASE_BRANCH`.
- `agent-review-pr.sh` is self-test-verified to never invoke `gh pr merge`
  directly (see its `--self-test`); the only merge-adjacent action it can
  take is requesting GitHub-native auto-merge via `agent-merge-gate`, and
  only when `--enable-auto-merge` is passed and the gate's own risk
  evaluation (`agent-route` + `agent-policy-eval` + reviewer evidence)
  comes back `auto`.
- `agent:ready` (or whatever label an operator points `--label` at) is a
  maintainer-owned queue: nothing in this loop adds that label
  automatically. A human deciding an issue is ready for automated dispatch
  is the actual trust boundary, not anything enforced by these scripts.
- `governance.yaml`, `model-routing.yaml`, `capability-profiles.yaml`,
  and the `scripts/agent-*` control-plane scripts themselves are flagged
  high-risk/human-review by their own policy (see
  [`docs/provider-consumer-layout.md`](provider-consumer-layout.md)) — an
  agent must not edit them to grant itself more authority.

## Failure modes

- **Quota/auth wall**: both scripts preflight `claude` and `gh` auth before
  starting a billed session; a failure here exits before any cost is
  incurred.
- **Inner session timeout/turn cap**: `AGENT_INNER_TIMEOUT_SECONDS` and
  `AGENT_MAX_TURNS` bound a stuck session; hitting either is recorded as a
  `failure` outcome with a specific blocker, not a silent stop.
- **Stranded branch with no PR**: if the inner session pushes a branch but
  the process is killed before the PR is opened (timeout, host
  preemption), the next run's `--label`/issue-number invocation does not
  automatically resume that branch; check `AGENT_OUTCOME_DIR` and the
  branch list for recovery.
- **Push URL mismatch**: a host that authenticates over HTTPS via `gh`'s
  credential helper but has a `git@github.com:` SSH push URL configured
  will fail only at PR-publication time, after the whole session is spent.
  `agent-run-issue.sh` normalizes GitHub SSH push URLs back to HTTPS and
  preflights `git ls-remote` before starting a session, specifically to
  catch this before burning a session.
- **Reviewer evidence missing or unschema-valid**: `agent-review-pr.sh`
  validates evidence via `agent-review-stage` before ever calling the
  merge gate; an invalid file blocks the gate rather than defaulting to
  any particular decision.
