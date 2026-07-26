---
name: co-change-map
description: Use before editing a file with non-obvious blast radius; query historical co-change data to see which other files usually change alongside it.
---

# Co-Change Map

Use `.agents/repo-map/scripts/cochange.sh` to see which other tracked files
have historically changed in the same commits as a file you're about to
edit. This is a routing hint from git history, not a dependency graph.

## When to use

- You're about to edit a config, schema, or other file with callers/
  consumers that aren't obvious from reading it alone.
- A change feels self-contained but the file has a long history and you want
  a cheap check for hidden coupling before treating it as done.

Skip this when the file is new, clearly isolated, or the coupling is already
obvious from the code (e.g. an import graph you've already traced).

## Workflow

1. Run `bash .agents/repo-map/scripts/cochange.sh <path>`.
2. Read the `ratio` column: how often the candidate file changed in the same
   commit as `<path>`, out of `<path>`'s qualifying commits (`total`).
3. Open the top few candidates and check whether this edit should touch them
   too.

Example:

```sh
bash .agents/repo-map/scripts/cochange.sh docs/ci.md
```

## Guardrails

- This is historical correlation, not causation. A high ratio can mean real
  coupling (a doc and the workflow it documents) or just files that happen
  to land in the same PRs. Verify before assuming one implies the other.
- A small `total` makes the ratio noisy — treat `total` of 1-2 as weak
  signal, not a real pattern.
- Do not treat the output as authoritative or exhaustive. It only says what
  to check first.
