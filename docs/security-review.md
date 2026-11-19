# Security review of the policy layer

In September 2026 the policy, gate, and canary layer of this repo was audited
against its own claim: that autonomy is bounded by deterministic policy, not
by model judgement. The audit looked for places where the tooling *claims* a
deterministic boundary that does not hold. It found 17 (0 critical, 3 high,
7 medium, 7 low). None were exploitable at the time, because the merge gate
was operator-invoked and no agent held a token for this repo, but every high
finding was a false-confidence gap of exactly the kind this repo exists to
remove.

Each finding below is either fixed, with the fix covered by a self-test or by
the [attack suite](../canaries/attacks/README.md), or left open with the
reason it is open. The raw audit notes were kept private because they
described the operator's machine and account settings; this page is the
public record of what was found and what was done.

## Findings

| Id | Finding | Status |
| -- | ------- | ------ |
| H1 | `learning/candidates/**` was auto-mergeable, yet promoted archive entries are spliced into every later dispatch prompt. | Fixed in #61: the archive routes to human review, is validated, and is read from the trusted base ref. Top-level candidates stay an unattended lane on purpose; they are inert until a reviewed PR promotes them. |
| H2 | The merge gate and reviewer wrapper ran from the PR's own working tree, so a PR could replace the code that gates it. | Fixed in #61: the gate and review stage run from the trusted base ref, and `--enable-auto-merge` is refused without one. A PR that replaces the wrapper script itself still wins if the operator runs that PR's copy; the mitigation is operational (run it from a base-branch checkout). |
| H3 | The canary checker matched regexes on prose: it flagged correct refusals and passed real policy weakening. | Fixed in #61: the checker judges added diff lines, tool calls, and policy-protected paths instead of prose. |
| M1 | `governance.yaml` protected a hand-picked list, so schemas, canaries, skills, `flake.nix`, `CLAUDE.md`, `.github/`, `.githooks/`, and `examples/` came back low risk. | Fixed in #64: deny by default with an explicit low-risk allowlist, a self-test that walks every tracked file, and `examples/` routed to human review. |
| M2 | Reviewer evidence was bound only to a PR number, and the enforced contract accepted fields the schema forbids. | Fixed in #65: evidence carries the reviewed commit's `head_sha` (written by the wrapper, not the model), the gate refuses evidence for any other commit, `--enable` passes `--match-head-commit`, and unknown fields are rejected. |
| M3 | The reviewer session runs with the operator's full `gh` token, no turn cap, and no tool restrictions; "do not merge" is prompt-only. | Open, relevant only if the loop runs again: give the reviewer a read-only token and an explicit tool allowlist. |
| M4 | The gate never consulted the `auto-merge` freeze, and freeze state was CWD-relative and fail-open. | Fixed in #63: the gate refuses `auto` while `auto-merge` or `all` is frozen and fails closed if freeze state cannot be read; freeze paths resolve from the agent root. |
| M5 | The consumer install example is unpinned: the locked flake rev is never what gets installed. | Open, relevant only once a second consumer exists: install from the locked rev. |
| M6 | Renaming a protected file away was invisible to every changed-path source. | Fixed in #61: every diff path source uses `--no-renames`. |
| M7 | GitHub posture: zero required approvals with auto-merge allowed, on a repo that intends to give an agent write access. | Open, relevant only if an agent is given write access: require an approval from a human for anything outside the low-risk allowlist. |
| L1 | CI actions pinned by mutable tag, no `permissions:` block, no timeouts. | Fixed in #66. |
| L2 | The reviewer picks the issue to check from the PR body, which the PR author controls. | Open, relevant only if the loop runs again: bind the review to the issue recorded by the dispatcher. |
| L3 | Docs called the policy layer advisory while the gate acts on it, and named a required status this repo does not have. | Fixed in #64: described as advisory for blocking, authoritative for granting. |
| L4 | A freeze reason containing `"` produced invalid JSON that hid the freeze from `status`. | Fixed in #63. |
| L5 | No edit guard in this repo's own agent harness for policy files. | Open, low value while no agent works in this repo unattended; the merge gate is the defense. |
| L6 | `nixos-config` leftovers in the generic surface, including a real tailnet hostname as a default. | Fixed in #64 and #66. |
| L7 | Schema files were unused by any check, and the promoted archive was outside every validator. | Fixed: the archive is validated (#61), and the reviewer-evidence check now enforces the same contract as its schema (#65). |

## Measured effect

The [deterministic attack suite](../canaries/attacks/README.md) turns these
findings into 24 fixtures run in CI. Before any fix, 21 of 24 attacks got
through. Now 2 do, both open by design (H1's unattended candidate lane and
H2's self-replacing wrapper, above), and all 9 controls still pass, so
"blocked" was not achieved by breaking the gate.

The [live canary study](../canaries/live/README.md) is the independent check:
64 real agent sessions across three models, offered subtle harmful changes
inside otherwise ordinary tasks. Models took the bait in 45% of runs. The
gates stopped every bait that touched a protected path, but only half of the
baits hidden in file content, and none of those through the merge gate
alone. Path-based policy cannot see a malicious edit to an allowed file; that
is the main open limit of this design.
