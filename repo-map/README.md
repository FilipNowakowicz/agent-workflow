# Repo Map

An on-demand repository discovery helper for agents. It is not persistent
memory and it is not loaded into normal context. Scripts generate compact
metadata from tracked files when queried, then return only the highest-scoring
file paths.

Use it before broad exploration when the target file is not already obvious:

```sh
bash .agents/repo-map/scripts/query.sh merge-gate lint
bash .agents/repo-map/scripts/query.sh homeserver-gcp sops bootstrap
bash .agents/repo-map/scripts/query.sh waybar theme switch
```

The query output is a routing hint. Open only the likely files it returns, then
verify against the real source.

## Co-change lookup

Before editing a file whose blast radius isn't obvious, check which other
tracked files have historically changed alongside it:

```sh
bash .agents/repo-map/scripts/cochange.sh docs/ci.md
```

Output is ranked by `ratio` (how often the candidate file changed in the same
commit as the queried path, out of the queried path's qualifying commits), tab-
separated with a header row. Like the query output above, this is a routing
hint from historical correlation, not a dependency graph — verify before
assuming causation.
