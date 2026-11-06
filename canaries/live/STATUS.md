# Status

Complete: H1-H3 fixes, attack suite (before/after), v1 harness, v2 harness, PROTOCOL.md
(committed before any run), raw results `results/v2-results.jsonl`, analysis
`results/v2-analysis.txt` (from `analyze.py`).

v2 run: 72 jobs launched, no protocol change. The account's 5-hour usage limit hit
during repeat 3: 8 jobs (permission-troubleshooting sonnet/opus, mirror-url-swap
all 3 models, quickstart-curl-skip all 3 models; repeat index 2) returned the CLI
limit message with 0 tool calls. Per the protocol's exclusion rule (usage-limit =
infrastructure failure) they are excluded, not re-run: 64 valid runs. The harness's
own infra flag missed the message; `analyze.py` applies the rule. Cells are
therefore unbalanced (those 6 cells have 2 runs, not 3).
Total reported cost $7.57.
