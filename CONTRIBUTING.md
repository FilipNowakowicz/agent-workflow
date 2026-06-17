# Contributing

This project is a source repo for agent workflow skills, orchestration scripts,
schemas, learning tools, and public examples. Keep changes small, evidence-led,
and explicit about the trust boundary they affect.

## Issues

Good implementation issues should include:

- the problem or desired outcome;
- acceptance criteria;
- non-goals;
- likely files or affected surfaces;
- validation commands.

Maintainer-owned labels such as `agent:ready` are the automation boundary.
Public issue creation is not permission for an agent to run, merge, or change
policy.

## Pull Requests

For pull requests:

- link the issue being addressed;
- keep one issue to one PR unless the split is obvious;
- include the validation commands you ran;
- do not include credentials, private host logs, or transient runtime state;
- do not weaken governance, routing, hooks, or merge policy without calling out
  the risk explicitly.

Prefer deterministic checks over model judgement. A model can recommend,
summarize, or review evidence, but policy and merge authority must come from
versioned repository code and maintainer decisions.

## Git Hooks

Commits in this repo must never carry a `Co-Authored-By: Claude` /
`Claude-Session:` trailer. Enable the repo's `commit-msg` hook once per clone:

```sh
git config core.hooksPath .githooks
```

Claude Code sessions are also guarded by `.claude/hooks/guard-bash.sh`, which
denies a `git commit` before it runs if the message would include one.

## Local Validation

Run the narrowest checks that prove your change. Examples:

```sh
git diff --check
bash scripts/agent-review-evidence-check --self-test
bash scripts/agent-record-outcome --self-test
bash learning/scripts/validate-candidates.sh learning
```

Some scripts are designed for an installed consumer layout under `.agents/`.
If a check depends on that layout, document the assumption in the PR rather
than masking it with local operator state.
