The endgame workflow — what to build toward

  Picture it as a closed loop with seven layers. You currently have strong versions of 1, 3, 4-(a), and 5-(a). The gaps are the connective tissue.
  
  1. Intent. You write a paragraph of goal ("I want X"), and an intake agent interrogates you — not the other way around — until it can emit epics and child issues that pass a readiness
  lint: acceptance criteria present, non-goals stated, proving check named, risk tier assigned. Nothing enters the queue without passing that lint; issue quality is the throughput limiter
  of everything downstream. Your issue-tdd skill is already 80% of this — what's missing is making readiness machine-checked (a label the linter applies, not you).

  2. Dispatch. A tailnet-side dispatcher (systemd timer on main or the homeserver — never a GitHub-side trigger, per the hijack disclosures) drains the queue: picks ready issues by
  priority, starts a worker, enforces budgets (max sessions/day, max tokens/issue, max concurrent VMs). Crucially it also generates work: flake-update breakage, CVE reports, drift
  detection, and liveness-gate failures file their own issues. At steady state, most of the queue is machine-filed; you mostly file direction-setting epics.
  
  3. Execution. What you have today, hardened: disposable least-privilege workers, one issue → one session → one PR, and every session emits a structured outcome record (issue, result, PR,
  cost, duration, blocking reason) instead of an exit code. When the queue is deep, the dispatcher scales horizontally — N short-lived VMs are better than one long-lived one, because your
  security model is per-host and your state is "a clone + secrets," which you've now proven bootstraps from nothing.
  
  4. Verification — where the real frontier is. Three gates, in order: merge-gate (mechanical truth — builds, tests, invariants); a reviewer agent with fresh context and adversarial 
  instructions — it must quote each acceptance criterion with evidence from the diff, and it's rewarded for finding reasons not to merge; and the autonomy policy: a declarative, versioned
  map from path-class × change-size × track-record → merge authority. Docs and scripts auto-merge after review-agent approval; modules and profiles need N consecutive clean merges in that
  class before the gate widens; secrets/, sudo, ACLs always queue for you, forever. The policy itself lives in the repo, enforced like your sops invariants — the boundary is programmable,
  auditable, and earned. Nobody has this today; it's the thing worth being first at.

  5. Learning & memory. Four distinct stores, each with its own integrity rule:
  - Session context — ephemeral, dies with the run.
  - Repo artifacts (assertions > hooks > skills > docs) — the shared, versioned long-term memory. This is the only store that changes agent behavior, and it only changes through a merged
  PR. Your candidates pipeline is the write path: capture (automatic, already live) → scheduled review session → strong candidates become issues → the loop implements them → you merge.
  Self-improvement at machine speed, integrity gated at exactly one point.
  - Private agent memory — per-agent context like "deploy-rs hangs in this harness" (my memory directory plays this role).
  - Telemetry — the outcome records, which feed both dashboards and the track record that the autonomy policy consumes. That's the link most people miss: learning isn't just lessons, it's
  the statistical evidence that earns wider gates.
  
  6. Observability. Your LGTM stack grows one small dashboard: sessions, outcomes, cost, time-to-merge, unattended-merge rate, merge-gate failure rate. Plus a weekly digest agent that
  writes you three paragraphs: what merged, what's blocked and why, what the learning loop promoted. You read the digest instead of the transcripts.
  
  7. The liveness gate. A scheduled cheap smoke of the dormant path (cold start → script ship → clone bootstrap → fail-fast, ~30s of VM time) so the system proves itself runnable every
  week. Today demonstrated why: three fatal bugs lived undetected in the "working" system because nothing exercised the runtime path.
  
  Your role at endgame: write goals, answer the intake agent's questions, merge the high-risk tier, read the weekly digest, and occasionally audit a random sample of auto-merged PRs
  (calibration — trust, but verify on a schedule). Everything else is the machine's. The KPI to drive toward is unattended merge rate with zero post-merge reverts; those two numbers in
  tension are the whole game.
  
  The separate-repo question

  Yes — but extract an engine, not a copy, and not yet.
  
  The right structure is a provider/consumer split. A new repo (agent-loop, say) is a flake exporting: the skills tree (issue-tdd, issue-driven-development, verification-loop, learning
  capture/review), the entrypoint scripts, the learning-candidate schema + tooling, the reviewer rubric, the dispatcher as a NixOS module, and eventually the autonomy-policy evaluator. This
  repo then consumes it as a flake input, exactly like any other dependency — and keeps what's genuinely local: validation commands, the risk-tier map for these paths, host runbooks,
  secrets.
  
  Why a separate repo is right (beyond tidiness): the workflow gets versioned releases, so a loop improvement can't break your infra repo mid-flight — and your existing flake-update
  auto-merge becomes the staged-rollout mechanism for the workflow itself, which is a beautiful reuse. It also unlocks the best dogfood there is: the agent-loop repo's own backlog gets
  maintained by the loop it implements. And it's the shareable artifact if you ever want this to be more than personal infra — the niche of "self-hosted, security-first agent loop" is wide
  open while everyone else parks repo-wide tokens in GitHub Actions runners.

  Why not yet: you have exactly one merged agent PR. Abstraction boundaries extracted from n=1 are guesses, and every wrong guess in a shared flake costs double (change the engine, then
  re-pin the consumer). Let the loop digest 20–30 issues here first — the recurring patterns versus one-off hacks will be obvious by then — and ideally start a trivial second consumer (any
  small repo of yours) at extraction time, because a second consumer is the only honest test that something generalized. Mechanically the migration is cheap whenever you do it: .agents/ and
  scripts/agent-* move almost verbatim, which is itself a sign the current layout is already well-factored.

  If you want a forcing function: when the learning-review pipeline starts proposing changes to the skills themselves rather than to this repo's configs, that's the signal the workflow has
  become its own product and deserves its own repo, its own issues, and its own agent loop.
  
