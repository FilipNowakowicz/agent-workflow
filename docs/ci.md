# CI

`.github/workflows/ci.yml` runs three jobs on every pull request and on push
to `main`. Every job is a deterministic, local-reproducible check: none of
them call Claude or Codex, need a GitHub write token, or touch GCP, SSH, or
any other private host state. All three jobs (`whitespace`, `self-tests`,
`nix-flake-check`) are required branch-protection checks on `main`: a PR
cannot merge until they pass and the branch is up to date. Repo admins are
exempt from the PR requirement (`enforce_admins: false`) so a maintainer can
still push directly to `main` when needed.

## Running the same checks locally

Whitespace / conflict markers introduced by your change (compare against the
common ancestor with `main`, or pass any other base commit):

```sh
git diff --check "$(git merge-base origin/main HEAD)" HEAD
```

Control-plane, orchestration, and learning self-tests (the loop below includes
`scripts/agent-attack-suite --self-test`, which runs the deterministic attack
fixtures in [`canaries/attacks/`](../canaries/attacks/README.md) against the
gates and fails if any attack marked `expect=blocked` succeeds):

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
bash learning/scripts/validate-candidates.sh --self-test
bash learning/scripts/index-candidates.sh --self-test
bash learning/scripts/scaffold-promotion-check.sh --self-test
bash learning/scripts/check-candidate-liveness.sh --self-test
bash learning/scripts/query-candidates.sh --self-test
bash learning/scripts/review-candidates.sh --self-test
bash repo-map/scripts/validate.sh
bash install.sh --self-test
```

Flake check, and the flake `paths` output smoke test (see
[`docs/provider-consumer-layout.md`](provider-consumer-layout.md)):

```sh
nix flake check
bash check-flake-outputs.sh
bash check-flake-outputs.sh --self-test
```
