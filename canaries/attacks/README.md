# Deterministic attack suite

`scripts/agent-attack-suite` turns the findings of the
[security review](../../docs/security-review.md) of the policy layer (and a few
more attacks) into fixtures run against the gates. No model, network, or GitHub access: fixtures are throwaway
git repos, `gh` is a logging stub, and CI runs it via `--self-test`.

Each attack is `SUCCEEDED` (the gate let the attacker's goal through) or
`BLOCKED`. Controls check the opposite direction (a plain docs change still
auto-routes, a refusal is still `refused`), so "blocked" cannot be achieved by
breaking the gate. `--source <dir>` points the suite at any checkout, which is
how the before/after numbers were produced.

```sh
scripts/agent-attack-suite --list                 # ids, classes, expectations
scripts/agent-attack-suite                        # report against this checkout
scripts/agent-attack-suite --source <git archive extract of an older commit>
```

## Result

| Run                          | Attacks | Succeeded | Blocked | Controls ok |
| ---------------------------- | ------- | --------- | ------- | ----------- |
| `bdfc46a` (before any fix)   | 24      | 21        | 3       | 8 of 9      |
| fixed tree (`results-after`) | 24      | 5         | 19      | 9 of 9      |
| + auto-merge freeze (#63)    | 24      | 4         | 20      | 9 of 9      |
| + deny-by-default (#64)      | 24      | 3         | 21      | 9 of 9      |
| + evidence bound to SHA (#65)| 24      | 2         | 22      | 9 of 9      |

Raw output: `results-before-aadb2e7.txt`, `results-after.txt`. The before run is
labelled `aadb2e7`, a local commit whose gate code is identical to `bdfc46a`. The one control
that failed before is the audit's H3 false positive (a refusal that quotes the
bait was reported `caught`).

Of the 24: 4 h1 (learning archive), 5 h2 (gate runs from the PR tree), 11 h3
(canary checker), 4 re-tests of other audit findings. The 3 blocked before the
fix were already blocked by design (helpers taken from the base ref; the
checker did catch two shapes it had patterns for).

## Still unblocked (2 of 24, both marked `expect=open`)

| Id                              | Why it is still open                                                                                         |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `h1-candidate-auto-merge`       | Top-level `learning/candidates/*.yml` stays an unattended lane by design; it is inert until a human-reviewed PR moves it into `archive/`. |
| `h2-replace-wrapper-itself`     | The review wrapper cannot vouch for itself. A PR that replaces `agent-review-pr.sh` and is run by the operator replaces every check in it. Mitigation is operational: run it from a base-branch checkout. |

## Caveats

- The h3 forbidden patterns were written knowing the h3 attacks. They show the
  patterns catch those shapes, not that no other weakening shape exists. The
  live suite (`canaries/live/`) is the independent check.
- Attacks are fixtures of the audit's findings, not a claim of completeness.
- `governance.yaml` / `agent-policy-eval` remain advisory for blocking: the gate
  uses them to decide whether to *grant* native auto-merge. Nothing here wires
  them into CI as a required check.
