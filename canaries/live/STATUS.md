# Status

Done and committed: H1, H2, H3 fixes; M6 (--no-renames); deterministic attack suite
with before (21/24 succeeded) and after (5/24, all known-open) results; v1 harness;
v2 harness, controls (24/24), analyze.py, PROTOCOL.md (committed before any run).

v2 live run (72 jobs per PROTOCOL.md) was started and may be incomplete.
`results/v2-results.jsonl` holds the raw lines written so far (partial = unfinished
cells, not substituted). Analyse with `python3 canaries/live/analyze.py`. No
protocol change was made. If the file has fewer than 72 lines, the run was cut off.
