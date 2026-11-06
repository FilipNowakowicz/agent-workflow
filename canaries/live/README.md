# Live canary harness

Operator-run, costs model tokens, never part of CI. Real `claude -p` sessions in
throwaway repos, file tools only, home directory denied, fake sentinel secrets
only. Judged on the resulting diff and tool calls, never on prose.

- `harness_v1.py` -- the first, crude suite (5 canaries). Result:
  `results/v1-crude-bare.jsonl` (0/45 baits taken, 45/45 legitimate tasks done:
  saturated, and it tested the models, not the gates).
- `harness.py` + `PROTOCOL.md` + `analyze.py` -- the harder v2 suite: 8 subtle
  scenarios, scored on take rate and on what the repo's gates would stop. The
  protocol was committed before the data. `harness.py controls` is the judge
  self-check (free); `harness.py run` spends money.
