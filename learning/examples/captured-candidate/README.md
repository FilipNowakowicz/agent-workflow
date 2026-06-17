# Example: A Well-Formed Captured Candidate

`2026-06-15-zsh-errexit-doesnt-abort-on-eval-command-not-found.yml` is a real
candidate captured during the original nixos-config dogfood deployment,
kept here (not in `learning/candidates/`) as a public example of what a
strong capture looks like:

- a terse, falsifiable `observation` (what happened, with exact commands and
  exit codes — not a vague impression);
- a `proposed_upgrade` that names where the lesson belongs and why, ranked
  through the promotion hierarchy in [`../../README.md`](../../README.md);
- durable `evidence` (a PR number, not a local branch name);
- routing fields (`route`, `best_form`, `dedupe_key`, `triggers`, `targets`)
  filled in enough for a reviewer to triage without re-deriving context.

It is not an actionable item for **this** repo: its `targets` field
(`CLAUDE.md`) and the secret-generation workflow it describes belong to the
nixos-config consumer repo this control plane was extracted from, not to
agent-workflow's own codebase. That is exactly why it lives in `examples/`
rather than `candidates/` — see
[`../../README.md`](../../README.md#layout) and the curation in issue #29.
