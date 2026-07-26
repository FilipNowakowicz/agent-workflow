# Backlog: deferred ideas

Ideas that are part of the original design but deliberately not built yet,
kept here instead of a stale roadmap doc. Nothing here should be read as "in
progress" — each item states its own trigger for when it's worth picking up.
Current build status of everything that *is* built lives in README's
["How much is built"](../README.md#how-much-is-built) section.

## Learned routing: policy/dispatch consuming outcome stats

`scripts/agent-outcome-stats` (per-path-class success/failure aggregation)
and `agent-route --outcome-dir` (advisory `path_class_stats` annotation) are
built, self-tested, and have been run against real accumulated telemetry —
see the README status section for the concrete fix that came out of that
first run. What's still open is the deeper loop: policy or dispatch actually
*changing a decision* (e.g. requiring human review below some success-rate
threshold) based on those stats.

**Trigger to pick this up:** a path class accumulates enough samples (more
than the ~11 seen so far for the one class with a real signal) that a
threshold-based policy change wouldn't just be noise. Also worth checking
before automating on `success_rate` alone: a low rate can reflect a
config/timeout problem rather than a risk problem — verify the `blocker`
field distribution first, not just the aggregate rate.

## Branch tournaments / benchmarks

Not the default path — expensive by design. Useful only for:

- high-value changes
- benchmarking model/router changes
- major agent-loop improvements
- issues that already failed once under the normal path

Flow: same issue, multiple plans/implementations on separate branches, same
deterministic checks, a reviewer compares results, the best branch is kept
and the others closed, telemetry feeds back into routing.

**Acceptance criteria, when built:**

- can replay old issues against different model routes
- can compare pass rate, cost, diff size, repair loops across branches
- results feed routing stats
- disabled by default

**Trigger to pick this up:** token budget stops being the binding
constraint, or a specific hard issue has failed once under the normal path
and a comparison is worth the spend.

## Extracting a separate `agent-loop` repo

Do not extract yet. The right structure, when it happens, is a
provider/consumer split — a new repo exporting the skills tree, entrypoint
scripts, learning-candidate tooling, the reviewer rubric, and eventually the
autonomy-policy evaluator, consumed as a flake input by repos that keep only
what's genuinely local (validation commands, path risk tiers, host
runbooks, secrets). That's effectively what *this* repo already is relative
to `nixos-config` — see README's provider/consumer framing — so this item is
about a second hop: extracting the engine from this repo into something even
more generic, once a second real consumer exists.

Target shape (sketch, not a commitment):

```text
agent-loop/
  flake.nix
  modules/
    agent-dispatcher.nix
    agent-worker.nix
  schemas/
    outcome.schema.json
    issue-readiness.schema.json
    autonomy-policy.schema.json
  skills/
    issue-tdd/
    verification-loop/
    learning-review/
  scripts/
    agent-readiness-lint
    agent-route
    agent-policy-eval
    agent-record-outcome
  examples/
    minimal-consumer/
    nixos-config-consumer/
```

**Trigger to pick this up:** 20-30 real issues completed through this repo's
own loop, patterns stabilised, and at least one second consumer repo exists.
Mechanically the migration should be cheap whenever it happens — the current
provider layout (`skills/`, `scripts/agent-*`) is already close to this
shape, which is itself evidence it doesn't need to happen early.

## Success metrics (north star)

Primary KPIs, in tension with each other by design:

- unattended merge rate (maximise)
- post-merge revert rate (target: zero)
- policy/privilege-boundary violation rate (target: zero)

Secondary metrics worth tracking as the loop runs more:

- cost per merged PR
- time to merge
- human review minutes saved
- validation failure rate / review failure rate
- repair loops per issue
- model success rate by task class
- blocked issue distribution

`scripts/agent-outcome-dashboard` and `scripts/agent-weekly-digest` already
surface some of these from real outcome records; this section is the target
framing for judging whether the loop is actually working, not a description
of a dashboard that exists.
