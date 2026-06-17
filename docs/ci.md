# CI

`.github/workflows/ci.yml` runs three jobs on every pull request and on push
to `main`. Every job is a deterministic, local-reproducible check: none of
them call Claude or Codex, need a GitHub write token, or touch GCP, SSH, or
any other private host state. It is not yet a required branch-protection
check (see issue #27's non-goals) — it exists so regressions are caught
automatically before that is wired up.

## Running the same checks locally

Whitespace / conflict markers introduced by your change (compare against the
common ancestor with `main`, or pass any other base commit):

```sh
git diff --check "$(git merge-base origin/main HEAD)" HEAD
```

Control-plane, orchestration, and learning self-tests:

```sh
for f in scripts/agent-*; do
  [[ -x $f ]] || continue
  grep -q -- '--self-test' "$f" || continue
  bash "$f" --self-test
done
bash orchestration/agent-session.sh --self-test
bash orchestration/agent-run-issue.sh --self-test
bash orchestration/agent-review-pr.sh --self-test
bash learning/scripts/validate-candidates.sh learning
bash learning/scripts/scaffold-promotion-check.sh --self-test
bash repo-map/scripts/validate.sh
```

Flake check:

```sh
nix flake check
```
