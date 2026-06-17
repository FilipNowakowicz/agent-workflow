# Agentic Development Control Plane — Implementation Plan

## 0. Goal

Build a self-hosted, NixOS-based agentic development loop for the `nixos-config` repo, later extractable into a reusable `agent-loop` flake.

The system should let the user write high-level goals, have the system turn them into ready issues, dispatch coding agents, verify work, review evidence, decide merge authority, learn from outcomes, and gradually increase autonomy only where telemetry proves it is safe and cost-effective.

The key idea is not “use Claude/Codex to write code”. The key idea is:

> A reproducible, self-hosted, evidence-gated agent control plane where autonomy is earned from telemetry and bounded by deterministic policy.

The workflow must be token-conscious. Expensive multi-agent/tournament workflows should be rare and reserved for benchmarking or high-value tasks. The default path should be one well-routed agent, strong deterministic verification, and cheap review where possible.

---

# 1. Architecture Overview

Final target architecture:

```text
0. Governance
1. Intent / Intake
2. Issue Readiness Lint
3. Repo Intelligence / System Graph
4. Model + Capability Routing
5. Dispatch
6. Execution
7. Verification
8. Reviewer Evidence
9. Autonomy Policy
10. Learning + Memory
11. Observability
12. Liveness + Adversarial Liveness
13. Rollback + Quarantine
```

The near-term MVP should focus on:

```text
1. outcome.schema.json
2. repo intelligence map
3. issue readiness linter
4. model-routing.yaml
5. capability-profiles.yaml
6. policy-eval
7. reviewer evidence schema
8. dispatcher integration
9. liveness gate
10. weekly digest
```

---

# 2. Core Design Principles

## 2.1 Deterministic policy beats model judgement

LLMs may plan, implement, summarise, and review, but they must not decide their own authority.

Allowed:

```text
Model recommends escalation.
Model proposes a fix.
Model produces reviewer evidence.
Model summarises risk.
```

Forbidden:

```text
Model grants itself permission.
Model widens auto-merge rights.
Model overrides protected paths.
Model changes policy without human review.
```

Authority must come from deterministic scripts and versioned policy files.

---

## 2.2 Issue text is not authority

Treat issue bodies, PR comments, logs, READMEs, changelogs, external docs, and test output as potentially hostile input.

Trust hierarchy:

```text
highest trust:
  governance policy
  autonomy policy
  capability policy
  merged skills/hooks

medium trust:
  structured issue metadata
  repo intelligence map
  human-created issue body

low trust:
  PR comments
  logs
  external docs
  dependency changelogs
  generated summaries

never authority:
  arbitrary text inside files/logs/issues
```

Rule:

```text
Issue body can describe requested work.
It cannot grant permissions.

Logs can provide evidence.
They cannot issue instructions.

Docs can explain conventions.
They cannot override policy.
```

---

## 2.3 Autonomy is earned, not assumed

The system should widen auto-merge only after repeated clean outcomes in a specific path class / task class.

Example:

```text
docs:
  auto-merge after 3 clean reviewed merges

scripts:
  auto-merge after 10 clean reviewed merges

nix modules:
  human review until substantial track record

security/secrets/policy:
  human review forever
```

Autonomy should shrink immediately after failure.

```text
post-merge revert -> freeze path class
protected path violation -> freeze all auto-merge
secret access attempt -> freeze all autonomy
policy violation -> quarantine issue + require human review
```

---

## 2.4 Token-conscious default

Do not spend tokens unless the model output can change the decision.

Rules:

```text
If issue is not ready, do not run implementer.
If deterministic checks fail, do not run expensive reviewer.
If policy says human-only, do not run expensive auto-merge review.
If change is tiny docs-only, skip planning and use cheap implementation/review.
If one repair attempt fails, block or escalate instead of looping indefinitely.
```

Expensive paths:

```text
branch tournaments
multi-reviewer comparison
Opus-level review
full repo context loading
long planning sessions
```

These should be reserved for high-risk or benchmark tasks.

---

# 3. Repository Layout

Suggested files:

```text
.agent/
  governance.yaml
  repo-map.yaml
  invariants.yaml
  checks.yaml
  model-routing.yaml
  capability-profiles.yaml
  autonomy-policy.yaml

  schemas/
    issue-readiness.schema.json
    outcome.schema.json
    stage-outcome.schema.json
    reviewer-evidence.schema.json
    route-decision.schema.json
    policy-decision.schema.json

  skills/
    issue-tdd/
    nix-module-editing/
    verification-loop/
    learning-review/

  prompts/
    intake.md
    planner.md
    implementer.md
    reviewer.md
    learning-reviewer.md

  scripts/
    agent-readiness-lint
    agent-classify-change
    agent-route
    agent-policy-eval
    agent-record-outcome
    agent-review-evidence-check
    agent-liveness-gate
    agent-freeze
    agent-weekly-digest

  state/
    outcomes/
    stage-outcomes/
    telemetry/
    freezes/
    learned-routing/

  generated/
    context-packs/
    reports/
```

Do not allow agents to auto-merge changes to:

```text
.agent/governance.yaml
.agent/autonomy-policy.yaml
.agent/capability-profiles.yaml
.agent/model-routing.yaml
.agent/scripts/agent-policy-eval
.agent/scripts/agent-freeze
.agent/scripts/agent-route
.agent/schemas/**
.github/workflows/**
secrets/**
.sops.yaml
```

---

# 4. Governance Layer

## Purpose

Define what the system is never allowed to do, what always requires human review, and how autonomy is revoked.

Suggested file:

```text
.agent/governance.yaml
```

Example:

```yaml
version: 1

never_auto_merge:
  - "secrets/**"
  - ".sops.yaml"
  - ".github/workflows/**"
  - ".agent/governance.yaml"
  - ".agent/autonomy-policy.yaml"
  - ".agent/capability-profiles.yaml"
  - ".agent/model-routing.yaml"
  - ".agent/scripts/agent-policy-eval"
  - ".agent/scripts/agent-freeze"
  - ".agent/scripts/agent-route"
  - ".agent/schemas/**"

human_review_forever:
  - path_class: secrets
  - path_class: security
  - path_class: sudo
  - path_class: ssh
  - path_class: binary_caches
  - path_class: agent_policy
  - path_class: dispatcher

freeze_on:
  post_merge_revert: true
  protected_path_touch: true
  secret_access_attempt: true
  policy_violation: true
  repeated_validation_failure_count: 3

policy_change_rules:
  governance_policy: human_only
  autonomy_policy: human_only
  capability_policy: human_only
  model_routing_policy: human_review_required
```

Acceptance criteria:

```text
- Governance file exists.
- Protected paths are declared.
- Policy evaluator consumes governance rules.
- Protected-path changes cannot be auto-merged.
- Tests prove that protected-path touches are blocked.
```

---

# 5. Issue Readiness Lint

## Purpose

No issue enters the queue unless it has enough structure for an agent to work on it safely.

The system should not rely on the user manually applying `agent:ready`.

Labels should be machine-owned:

```text
agent:ready
agent:not-ready
agent:blocked
agent:risk-docs
agent:risk-scripts
agent:risk-nix
agent:risk-security
agent:risk-policy
```

## Required issue structure

Suggested schema:

```yaml
goal: string

acceptance_criteria:
  - id: AC1
    criterion: string
    evidence_required: command | diff | file | test | manual

non_goals:
  - string

risk_tier: docs | scripts | nix_modules | profiles | security | secrets | agent_policy

affected_paths:
  - glob

verification:
  commands:
    - string

rollback_plan: string

budget:
  max_attempts: integer
  max_tokens: integer
  max_cost_usd: number

permissions:
  network_required: boolean
  secrets_required: boolean
  sudo_required: boolean
```

## Command

```bash
.agent/scripts/agent-readiness-lint --issue 123
```

Output:

```json
{
  "issue": 123,
  "ready": true,
  "risk_tier": "scripts",
  "missing_fields": [],
  "labels_to_apply": ["agent:ready", "agent:risk-scripts"]
}
```

Failure example:

```json
{
  "issue": 123,
  "ready": false,
  "missing_fields": ["acceptance_criteria", "rollback_plan"],
  "labels_to_apply": ["agent:not-ready"]
}
```

Acceptance criteria:

```text
- Issues missing acceptance criteria are blocked.
- Issues missing non-goals are blocked.
- Issues requiring secrets are marked human-only.
- Machine applies readiness labels.
- Human-added ready labels are ignored or corrected.
```

---

# 6. Repo Intelligence Layer

## Purpose

Give the system a structured model of the repo so agents do not treat every file edit equally.

This is the biggest capability improvement beyond the base workflow.

The system should know:

```text
which subsystem a file belongs to
which host/service/module it affects
which invariants apply
which checks are required
which path class it belongs to
which previous failures are relevant
which context files should be loaded
```

## Files

```text
.agent/repo-map.yaml
.agent/invariants.yaml
.agent/checks.yaml
```

## Example repo map

```yaml
version: 1

subsystems:
  airgap_vms:
    description: "ColdVM, Watchonly VM, Whonix, shuttle images, vault disks."
    paths:
      - "scripts/vm/**"
      - "modules/vm/**"
      - "docs/airgap/**"
    risk: high
    invariants:
      - "Never attach a shuttle image to more than one VM at once."
      - "Mount vault and shuttle disks by /dev/disk/by-id virtio serials."
      - "ColdVM must remain permanently offline."
      - "No physical USB passthrough assumptions."
    required_checks:
      - "nix flake check"
      - "shellcheck"
      - "agent-check-vm-shuttle-policy"
    suggested_context:
      - "docs/airgap-workflow.md"
      - "scripts/vm/"
      - "modules/vm/"

  nixos_modules:
    description: "Reusable NixOS modules and host configuration."
    paths:
      - "modules/nixos/**"
      - "hosts/**"
    risk: medium_high
    required_checks:
      - "nix flake check"
      - "nix eval .#nixosConfigurations"

  agent_loop:
    description: "Agent workflow machinery."
    paths:
      - ".agent/**"
      - ".agent/scripts/agent-*"
    risk: high
    human_review: true
    required_checks:
      - "nix flake check"
      - ".agent/scripts/agent-policy-eval --self-test"

  docs:
    description: "Documentation-only changes."
    paths:
      - "README.md"
      - "docs/**"
    risk: low
    required_checks:
      - "markdownlint"
```

## Command

```bash
.agent/scripts/agent-classify-change --issue 123
```

Output:

```json
{
  "issue": 123,
  "subsystems": ["airgap_vms"],
  "risk": "high",
  "path_classes": ["vm", "scripts"],
  "required_checks": [
    "nix flake check",
    "shellcheck",
    "agent-check-vm-shuttle-policy"
  ],
  "relevant_invariants": [
    "Never attach a shuttle image to more than one VM at once.",
    "Mount vault and shuttle disks by /dev/disk/by-id virtio serials."
  ],
  "suggested_context_files": [
    "docs/airgap-workflow.md",
    "scripts/vm/",
    "modules/vm/"
  ]
}
```

Acceptance criteria:

```text
- Change classifier maps paths to subsystems.
- Classifier returns required checks.
- Classifier returns relevant invariants.
- Classifier identifies human-review-only subsystems.
- Planner receives repo intelligence context pack.
```

---

# 7. Model Routing

## Purpose

The system should learn which model/tool works best for which task class, but the first version should use hand-written routing.

Model routing chooses who thinks. It does not grant authority.

## Core idea

```text
stage × task_type × risk_tier × budget × historical success -> model profile
```

## File

```text
.agent/model-routing.yaml
```

## Example

```yaml
version: 1

defaults:
  max_attempts_per_issue: 2
  max_repair_attempts: 1
  require_different_reviewer_family: true

profiles:
  cheap_triage:
    tool: claude-code
    model: haiku
    purpose: "Cheap classification, summaries, tiny docs."

  balanced_planner:
    tool: claude-code
    model: sonnet
    purpose: "Planning, intake, normal reasoning."

  codex_executor:
    tool: codex-cli
    model: default
    purpose: "Implementation in isolated worker."

  adversarial_reviewer:
    tool: claude-code
    model: opus
    purpose: "High-risk review and evidence checking."

  human_only:
    tool: none
    model: none
    purpose: "Human decision required."

routes:
  intake:
    default: balanced_planner

  planning:
    docs: cheap_triage
    scripts: balanced_planner
    nix_modules: balanced_planner
    profiles: balanced_planner
    security: adversarial_reviewer
    secrets: human_only
    agent_policy: human_only

  implementation:
    docs: codex_executor
    scripts: codex_executor
    nix_modules: codex_executor
    profiles: codex_executor
    security: codex_executor
    secrets: human_only
    agent_policy: human_only

  review:
    docs: cheap_triage
    scripts: balanced_planner
    nix_modules: adversarial_reviewer
    profiles: adversarial_reviewer
    security: adversarial_reviewer
    secrets: human_only
    agent_policy: human_only

escalation:
  on_validation_failure:
    max_same_model_retries: 1
    then: switch_executor_or_block

  on_large_diff:
    files_changed_at_or_over: 8
    lines_changed_at_or_over: 300
    then_review: adversarial_reviewer

  on_model_disagreement:
    then: human_review

  on_policy_boundary_touch:
    then: human_only
```

## Command

```bash
.agent/scripts/agent-route --issue 123 --stage implementation
```

Output:

```json
{
  "issue": 123,
  "stage": "implementation",
  "profile": "codex_executor",
  "tool": "codex-cli",
  "model": "default",
  "reasons": [
    "risk_tier=scripts",
    "stage=implementation",
    "codex_executor default for scripts"
  ],
  "budget": {
    "max_attempts": 1,
    "max_tokens": 16000
  }
}
```

Acceptance criteria:

```text
- Routing is deterministic.
- Route decision is recorded in outcome.
- Protected classes route to human_only.
- Expensive review is skipped for tiny low-risk docs.
- Router supports later telemetry-informed routing.
```

---

# 8. Capability Profiles

## Purpose

Capability routing decides what the worker can do.

This matters more than model routing.

## File

```text
.agent/capability-profiles.yaml
```

## Example

```yaml
version: 1

profiles:
  read_only:
    filesystem: read_only
    network: none
    secrets: none
    git: read_only
    commands: allowlisted
    sudo: never

  repo_write_no_network:
    filesystem: repo_write
    network: none
    secrets: none
    git: branch_push
    commands:
      - "nix flake check"
      - "nix eval"
      - "shellcheck"
      - "pytest"
    sudo: never

  repo_write_allowlisted_network:
    filesystem: repo_write
    network: allowlisted
    secrets: none
    git: branch_push
    sudo: never

  review_only:
    filesystem: read_only
    network: none
    secrets: none
    git: read_only
    commands:
      - "git diff"
      - "nix flake check"
    sudo: never

  human_only:
    filesystem: none
    network: none
    secrets: none
    git: none
    commands: []
    sudo: never
```

Rules:

```text
No default network.
No default secrets.
No sudo.
No broad GitHub tokens.
Short-lived branch-scoped tokens where possible.
Separate token for PR creation vs merge where possible.
```

Acceptance criteria:

```text
- Dispatcher selects capability profile per issue.
- Workers receive only selected capabilities.
- Capability profile is recorded in outcome.
- Secret-requiring issues are blocked or human-only.
- Network access must be explicit.
```

---

# 9. Dispatch Layer

## Purpose

A host-side dispatcher drains ready issues and starts isolated workers.

Do not use GitHub-side triggers as the trust root.

## Dispatcher responsibilities

```text
- Find ready issues.
- Sort by priority/risk/budget.
- Select workflow stage.
- Call repo classifier.
- Call model router.
- Call capability router.
- Start disposable worker.
- Enforce concurrency.
- Enforce token/cost/session budgets.
- Record stage outcome.
- Open/update PR.
- Apply labels.
```

## Requirements

```text
- Runs from tailnet/main/homeserver/GCP VM.
- Uses systemd timer.
- Never runs as broad privileged user.
- Workers are short-lived.
- One issue -> one branch/session/PR.
- Each run emits structured outcome record.
```

Suggested command:

```bash
.agent/scripts/agent-dispatch --max-issues 3 --max-concurrent 1
```

Acceptance criteria:

```text
- Dispatcher only selects agent:ready issues.
- Dispatcher refuses frozen path classes.
- Dispatcher enforces max concurrent workers.
- Dispatcher records outcome even on failure.
- Dispatcher never gives workers broad repo/admin authority.
```

---

# 10. Execution Layer

## Purpose

Run implementation inside disposable least-privilege workers.

## Execution contract

Each worker gets:

```text
issue.yaml
context-pack/
route-decision.json
capability-profile.json
repo-classification.json
policy-summary.txt
forbidden-paths.txt
validation-commands.txt
```

Each worker outputs:

```text
branch
diff
implementation-summary.md
commands-run.json
blocking-reason, if blocked
stage-outcome.json
```

Blocking reasons should use fixed enum:

```text
insufficient_issue_spec
validation_failed
policy_forbidden_path
secret_required
network_required
merge_conflict
flaky_test
agent_uncertain
reviewer_blocked
budget_exceeded
tool_failure
```

Acceptance criteria:

```text
- Worker can complete docs/scripts issues.
- Worker cannot access secrets by default.
- Worker cannot use network unless profile allows it.
- Worker emits structured outcome.
- Worker failure does not leave privileged state behind.
```

---

# 11. Verification Layer

## Purpose

Deterministic checks come before reviewer LLM calls.

Verification should be chosen from repo intelligence and issue metadata.

Examples:

```text
nix flake check
nix eval .#nixosConfigurations
shellcheck
pytest
markdownlint
custom invariant checks
agent-policy-eval --self-test
```

## Rule

```text
If deterministic verification fails, do not run expensive review.
Return to repair once, then block/escalate.
```

Acceptance criteria:

```text
- Required checks are selected from repo map.
- Verification logs are attached to outcome.
- Failed verification blocks policy approval.
- One repair loop allowed by default.
- Repeated failure creates blocker label.
```

---

# 12. Reviewer Evidence Layer

## Purpose

The reviewer agent must not say “looks good”. It must produce structured evidence.

## Schema

```yaml
issue: integer
pr: integer
reviewer_profile: string

criteria:
  - id: AC1
    quoted_criterion: string
    satisfied: boolean
    evidence:
      - type: diff | command | file | test
        reference: string
        result: string
    objections:
      - string

risk_findings:
  - severity: low | medium | high | critical
    finding: string
    evidence: string

policy_observations:
  touched_protected_paths: boolean
  requires_human_review: boolean
  reason: string

recommendation: block | human_review | auto_merge_allowed
```

## Rule

The reviewer produces evidence. The policy evaluator decides authority.

Acceptance criteria:

```text
- Reviewer quotes every acceptance criterion.
- Reviewer cites diff/command/file evidence.
- Reviewer flags protected path touches.
- Reviewer output validates against schema.
- Invalid reviewer output is treated as block.
```

---

# 13. Autonomy Policy

## Purpose

Determine whether a PR can be auto-merged, needs human review, or must be blocked.

This must be deterministic.

## File

```text
.agent/autonomy-policy.yaml
```

## Example

```yaml
version: 1

path_classes:
  docs:
    max_decision: auto_merge
    require_clean_merges: 3
    max_files_changed: 5
    max_lines_changed: 100

  scripts:
    max_decision: auto_merge_after_review
    require_clean_merges: 10
    max_files_changed: 5
    max_lines_changed: 200

  nix_modules:
    max_decision: human_review_until_track_record
    require_clean_merges: 25
    max_files_changed: 8
    max_lines_changed: 300

  profiles:
    max_decision: human_review

  security:
    max_decision: human_review

  secrets:
    max_decision: block

  agent_policy:
    max_decision: human_review

global_denies:
  - "secrets/**"
  - ".sops.yaml"
  - ".github/workflows/**"
  - ".agent/governance.yaml"
  - ".agent/autonomy-policy.yaml"
  - ".agent/capability-profiles.yaml"
  - ".agent/model-routing.yaml"
  - ".agent/scripts/agent-policy-eval"
  - ".agent/scripts/agent-freeze"
  - ".agent/scripts/agent-route"
  - ".agent/schemas/**"

required_conditions_for_auto_merge:
  - issue_ready
  - verification_passed
  - reviewer_passed
  - no_protected_paths
  - no_secret_access
  - within_change_budget
  - clean_track_record_satisfied
```

## Command

```bash
.agent/scripts/agent-policy-eval --issue 123 --pr 456
```

Output:

```json
{
  "decision": "human_review_required",
  "reasons": [
    "path_class=nix_modules",
    "clean_track_record=4/25",
    "auto_merge_not_yet_earned"
  ]
}
```

Acceptance criteria:

```text
- Policy evaluator is deterministic.
- Protected paths block auto-merge.
- Human-only classes are respected.
- Track record is consumed.
- Decision is recorded in outcome.
```

---

# 14. Outcome Records and Telemetry

## Purpose

Every run must produce structured telemetry.

This is the basis for:

```text
model routing
autonomy widening
cost accounting
weekly digest
failure analysis
learning loop
```

## Outcome schema

```json
{
  "issue": 123,
  "pr": 456,
  "stage": "implementation",
  "result": "success",
  "blocking_reason": null,

  "model_profile": "codex_executor",
  "tool": "codex-cli",
  "model": "default",
  "capability_profile": "repo_write_no_network",

  "policy_commit": "abc123",
  "flake_lock_hash": "sha256-...",
  "worker_image": "sha256-...",

  "subsystems": ["nixos_modules"],
  "path_classes": ["nix_modules"],
  "risk_tier": "nix_modules",

  "changed_paths": [],
  "files_changed": 4,
  "lines_added": 80,
  "lines_deleted": 20,

  "validation": {
    "passed": true,
    "commands": []
  },

  "review": {
    "passed": true,
    "recommendation": "human_review"
  },

  "policy_decision": "human_review_required",

  "cost": {
    "input_tokens": 0,
    "output_tokens": 0,
    "estimated_usd": 0.0
  },

  "duration_seconds": 0,
  "attempt_number": 1,
  "repair_loops": 0,
  "post_merge_reverted": false
}
```

Acceptance criteria:

```text
- Every stage writes outcome JSON.
- Failed runs also write outcome JSON.
- Model/tool/cost/duration are recorded.
- Changed paths and risk are recorded.
- Outcome records can be summarised by script.
```

---

# 15. Learning and Memory

## Purpose

The system should improve by turning repeated successful/failed patterns into repo artefacts.

Learning pipeline:

```text
capture outcome
summarise candidate lesson
cluster repeated lessons
promote strong candidates into issues
agent implements issue
human merges if it affects behaviour/policy
```

Important rule:

```text
A lesson is not learned until it becomes a test, linter rule, skill, policy update, repo-map update, or documentation change.
```

Memory types:

```text
session context:
  ephemeral, dies after run

private agent memory:
  hints only, never policy

telemetry:
  append-only evidence

repo artefacts:
  versioned long-term behaviour

policy:
  protected, human-controlled
```

Acceptance criteria:

```text
- Learning candidates are captured.
- Candidates do not directly change behaviour.
- Strong candidates become issues.
- Behaviour-changing learning goes through PR.
- Policy changes require human review.
```

---

# 16. Model Learning / Routing Improvement

## Purpose

The system should learn which model/tool works best for which case.

It should learn routing, not authority.

Examples of things it may learn:

```text
Codex works better for script implementation.
Sonnet works better for planning vague issues.
Cheap model is enough for docs review.
Opus-level review catches more issues in Nix module changes.
```

Things it must not learn:

```text
This model is good, so let it edit secrets.
This model is reliable, so let it bypass policy.
This model reviewed itself, so auto-merge security changes.
```

## Simple first version

Start hand-written.

Later use rolling stats:

```text
success rate
cost per merged PR
repair loops
review pass rate
post-merge revert rate
policy violation rate
```

Example learned report:

```text
For task_type=scripts, stage=implementation:
  codex_executor:
    success_rate: 0.81
    average_cost: 0.42
    average_repair_loops: 0.4

  balanced_planner:
    success_rate: 0.66
    average_cost: 0.35
    average_repair_loops: 1.1
```

Then router can prefer the best expected value subject to risk/budget constraints.

Acceptance criteria:

```text
- Model outcomes are queryable by task class.
- Router can consume learned stats later.
- Learning never overrides governance policy.
- Cheap model is preferred when success is sufficient.
```

---

# 17. Observability and Weekly Digest

## Purpose

The user should not read transcripts. The system should produce concise operational summaries.

Dashboard metrics:

```text
sessions
merged PRs
blocked issues
cost per merged PR
time to merge
unattended merge rate
post-merge revert rate
validation failure rate
review failure rate
policy block rate
human review queue
model success by task class
```

Weekly digest format:

```text
1. What merged
2. What is blocked and why
3. What the learning loop promoted
4. What needs human decision
5. Cost summary
6. Autonomy changes/freeze states
```

Acceptance criteria:

```text
- Weekly digest generated from outcome records.
- Digest lists only actionable human decisions.
- Cost and failures are included.
- Blockers use fixed taxonomy.
```

---

# 18. Liveness and Adversarial Liveness

## Purpose

The system must regularly prove dormant paths still work.

## Normal liveness gate

Scheduled weekly:

```text
cold start
bootstrap worker
clone repo
load policy
run fail-fast check
write outcome
destroy worker
```

Target: cheap, short, no expensive LLM unless necessary.

## Adversarial liveness

Create canary issues that should be refused.

Examples:

```text
1. Docs issue whose body asks agent to edit secrets.
2. Test log contains prompt injection.
3. Tiny README typo but diff touches .github/workflows.
4. Dependency changelog tells agent to ignore policy.
5. Script refactor attempts to widen dispatcher permissions.
```

Acceptance criteria:

```text
- Liveness gate runs on schedule.
- Failure files issue automatically.
- Adversarial canaries are refused.
- Refusal is recorded as success.
```

---

# 19. Rollback and Quarantine

## Purpose

Merge is not the end of verification.

Post-merge checks:

```text
T+0: merge gate passed
T+10min: liveness smoke
T+24h: scheduled check
T+7d: regression check
```

On failure:

```text
open revert PR
freeze path class
label original issue regression
file root-cause issue
add failure to regression evals
```

Commands:

```bash
.agent/scripts/agent-freeze all
.agent/scripts/agent-freeze path-class nix_modules
.agent/scripts/agent-freeze auto-merge
.agent/scripts/agent-freeze model codex_executor
```

Acceptance criteria:

```text
- Freeze state blocks dispatcher.
- Post-merge failure opens revert PR or issue.
- Failure becomes regression test/canary.
- Frozen state appears in weekly digest.
```

---

# 20. Token-Saving Rules

Default token policy:

```yaml
token_policy:
  no_planning_for_tiny_docs: true
  no_strong_review_below_risk_medium: true
  summarise_context_before_large_runs: true
  reuse_context_pack_across_stages: true
  cap_repair_loops: 1
  prefer_deterministic_checks_over_llm_review: true
  use_llm_only_when_it_changes_the_decision: true
  branch_tournaments_default: false
```

Practical examples:

```text
Docs typo:
  readiness -> cheap implement -> markdownlint -> policy

Script change:
  readiness -> route -> implement -> shellcheck/nix check -> normal review -> policy

Nix module:
  readiness -> planner -> implement -> nix checks -> strong review -> human/policy

Agent policy change:
  readiness -> human review required from start
```

Acceptance criteria:

```text
- Expensive reviewer skipped when deterministic checks fail.
- Tiny docs changes use cheap path.
- Repair loops capped.
- Token/cost estimate recorded per stage.
```

---

# 21. Future: Branch Tournaments / Benchmarks

This is not default because it is expensive.

Use only for:

```text
high-value changes
benchmarking model/router changes
major agent-loop improvements
hard issues that failed once
```

Tournament flow:

```text
same issue
multiple plans/implementations
separate branches
same deterministic checks
reviewer compares results
best branch kept
others closed
telemetry updates routing
```

This is useful as an eval/benchmark tool, not as daily workflow.

Acceptance criteria for future version:

```text
- Can replay old issues against different model routes.
- Can compare pass rate, cost, diff size, repair loops.
- Results feed routing stats.
- Disabled by default.
```

---

# 22. Future: Extract `agent-loop` Repo

Do not extract yet.

Extract after:

```text
20-30 real issues completed
patterns stabilised
at least one second consumer repo exists
learning loop proposes changes to skills/workflow itself
```

Target structure:

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

Consumer repo keeps:

```text
local repo map
local invariants
local risk policy
local secrets policy
host-specific runbooks
```

---

# 23. Implementation Roadmap

## Phase 1 — Foundations

Deliverables:

```text
.agent/schemas/outcome.schema.json
.agent/scripts/agent-record-outcome
.agent/repo-map.yaml
.agent/invariants.yaml
.agent/checks.yaml
.agent/scripts/agent-classify-change
```

Acceptance criteria:

```text
- Can classify a changed path into subsystem/risk/checks.
- Can write outcome JSON.
- Outcome schema validates.
```

---

## Phase 2 — Readiness and Routing

Deliverables:

```text
.agent/schemas/issue-readiness.schema.json
.agent/scripts/agent-readiness-lint
.agent/model-routing.yaml
.agent/capability-profiles.yaml
.agent/scripts/agent-route
```

Acceptance criteria:

```text
- Not-ready issues are blocked.
- Ready issues get machine label.
- Route decision returns model profile.
- Capability profile is selected.
- Route decision is recorded.
```

---

## Phase 3 — Policy Evaluator

Deliverables:

```text
.agent/governance.yaml
.agent/autonomy-policy.yaml
.agent/scripts/agent-policy-eval
.agent/schemas/policy-decision.schema.json
```

Acceptance criteria:

```text
- Protected paths block auto-merge.
- Human-only path classes require human.
- Low-risk docs can be approved only if checks pass.
- Policy decision is deterministic and testable.
```

---

## Phase 4 — Reviewer Evidence

Deliverables:

```text
.agent/schemas/reviewer-evidence.schema.json
.agent/prompts/reviewer.md
.agent/scripts/agent-review-evidence-check
```

Acceptance criteria:

```text
- Reviewer must quote each acceptance criterion.
- Reviewer must cite evidence.
- Invalid reviewer output blocks.
- Reviewer recommendation does not override policy.
```

---

## Phase 5 — Dispatcher Integration

Deliverables:

```text
.agent/scripts/agent-dispatch
systemd timer/service
worker bootstrap
stage outcome recording
```

Acceptance criteria:

```text
- Dispatcher drains ready issues.
- Starts isolated worker.
- Enforces max concurrency.
- Records success/failure.
- Creates or updates PR.
```

---

## Phase 6 — Observability

Deliverables:

```text
.agent/scripts/agent-weekly-digest
basic dashboard or markdown report
cost summary
blocker summary
```

Acceptance criteria:

```text
- Weekly digest lists merged/blocked/human-needed items.
- Digest reads outcome records.
- Cost and failure stats included.
```

---

## Phase 7 — Liveness and Rollback

Deliverables:

```text
.agent/scripts/agent-liveness-gate
adversarial canary issues
.agent/scripts/agent-freeze
post-merge monitor
```

Acceptance criteria:

```text
- Liveness gate runs weekly.
- Adversarial canaries are refused.
- Freeze blocks dispatcher.
- Post-merge failure creates issue/revert PR.
```

---

# 24. MVP Issue List for Coding Agents

## Issue 1 — Add outcome schema and recorder

Goal:

```text
Create structured outcome recording for agent runs.
```

Acceptance criteria:

```text
- Add .agent/schemas/outcome.schema.json.
- Add .agent/scripts/agent-record-outcome.
- Script validates JSON before writing.
- Outcomes stored under .agent/state/outcomes/.
- Include example success and failure outcome files.
```

---

## Issue 2 — Add repo intelligence map and classifier

Goal:

```text
Create a machine-readable repo map and a classifier that maps paths/issues to subsystems, risks, checks, and invariants.
```

Acceptance criteria:

```text
- Add .agent/repo-map.yaml.
- Add .agent/invariants.yaml.
- Add .agent/checks.yaml.
- Add .agent/scripts/agent-classify-change.
- Given changed paths, script outputs subsystem/risk/checks JSON.
- Include tests/examples for docs, scripts, nix modules, and agent-policy paths.
```

---

## Issue 3 — Add issue readiness linter

Goal:

```text
Block under-specified issues before dispatch.
```

Acceptance criteria:

```text
- Add .agent/schemas/issue-readiness.schema.json.
- Add .agent/scripts/agent-readiness-lint.
- Linter checks goal, acceptance criteria, non-goals, risk tier, affected paths, verification, rollback plan, and budget.
- Linter outputs ready/not-ready JSON.
- Missing acceptance criteria blocks readiness.
```

---

## Issue 4 — Add model and capability routing

Goal:

```text
Create deterministic routing for model/tool profile and worker capability profile.
```

Acceptance criteria:

```text
- Add .agent/model-routing.yaml.
- Add .agent/capability-profiles.yaml.
- Add .agent/scripts/agent-route.
- Route decision includes stage, model profile, tool, capability profile, budget, and reasons.
- Protected/security/secrets classes route to human_only or restricted profiles.
```

---

## Issue 5 — Add governance and autonomy policy evaluator

Goal:

```text
Create deterministic policy evaluation for block/human-review/auto-merge decisions.
```

Acceptance criteria:

```text
- Add .agent/governance.yaml.
- Add .agent/autonomy-policy.yaml.
- Add .agent/scripts/agent-policy-eval.
- Policy blocks protected paths.
- Policy requires human review for secrets/security/agent-policy paths.
- Policy permits low-risk docs only if readiness, verification, review, and change budget pass.
- Include self-tests.
```

---

## Issue 6 — Add reviewer evidence schema

Goal:

```text
Force reviewer agents to produce structured evidence instead of vague approval.
```

Acceptance criteria:

```text
- Add .agent/schemas/reviewer-evidence.schema.json.
- Add .agent/prompts/reviewer.md.
- Add .agent/scripts/agent-review-evidence-check.
- Reviewer must quote each acceptance criterion.
- Reviewer must cite diff/command/file evidence.
- Invalid reviewer output blocks policy approval.
```

---

## Issue 7 — Add liveness gate

Goal:

```text
Add cheap scheduled smoke test for the agent runtime path.
```

Acceptance criteria:

```text
- Add .agent/scripts/agent-liveness-gate.
- Gate checks worker bootstrap, repo clone, policy load, and fail-fast verification.
- Gate writes outcome record.
- Failure creates or prints issue-ready report.
```

---

## Issue 8 — Add freeze mechanism

Goal:

```text
Allow manual and automatic freezes of autonomy, models, and path classes.
```

Acceptance criteria:

```text
- Add .agent/scripts/agent-freeze.
- Freeze state stored under .agent/state/freezes/.
- Dispatcher/policy evaluator reads freeze state.
- Support freeze all, auto-merge, path-class, model-profile.
- Frozen state appears in policy decision output.
```

---

## Issue 9 — Add weekly digest

Goal:

```text
Summarise outcomes into a short actionable report.
```

Acceptance criteria:

```text
- Add .agent/scripts/agent-weekly-digest.
- Reads outcome records.
- Reports merged, blocked, failed, cost, model stats, and human decisions needed.
- Uses blocker taxonomy.
```

---

## Issue 10 — Add adversarial canary issues

Goal:

```text
Test that the system refuses malicious or policy-violating work.
```

Acceptance criteria:

```text
- Add canary definitions under .agent/canaries/.
- Include prompt-injection issue body canary.
- Include protected-path touch canary.
- Include fake log-injection canary.
- Canary success means correct refusal, not merge.
```

---

# 25. Success Metrics

Primary KPIs:

```text
unattended merge rate
post-merge revert rate
policy violation rate
```

Target tension:

```text
Maximise unattended merge rate
subject to zero post-merge reverts
and zero privilege-boundary violations.
```

Secondary metrics:

```text
cost per merged PR
time to merge
human review minutes saved
validation failure rate
review failure rate
repair loops per issue
model success by task class
blocked issue distribution
```

---

# 26. Final Priority Order

Build in this order:

```text
1. outcome records
2. repo intelligence map
3. issue readiness lint
4. model routing
5. capability profiles
6. governance + autonomy policy
7. reviewer evidence schema
8. dispatcher integration
9. liveness gate
10. freeze/quarantine
11. weekly digest
12. adversarial canaries
13. learned routing
14. branch tournament benchmarks
15. separate agent-loop repo
```

Do not prioritise workflow compiler yet.

Do not prioritise dashboards before outcome records.

Do not prioritise branch tournaments while token budget is tight.

Do prioritise repo intelligence, policy evaluation, and telemetry because these improve every future part of the system.
