{
  description = "agent-workflow: self-hosted, evidence-gated agentic development control plane — skills, orchestration, control-plane scripts, schemas, and a learning loop";

  # No inputs yet: this is a source-only provider flake. v2 will grow real
  # outputs here (the dispatcher/worker as NixOS modules, the policy evaluator
  # as a package) per PLAN.md §22 "Extract agent-loop Repo".
  outputs =
    { self }:
    {
      # Source trees exposed for consumption as a flake input by a downstream
      # repo (e.g. the nixos-config flake). The consumer pins this repo:
      #
      #   inputs.agent-workflow.url = "github:FilipNowakowicz/agent-workflow";
      #
      # then renders these back into its own `.agents/` tree:
      #
      #   ${inputs.agent-workflow.paths.skills}        -> .agents/skills
      #   ${inputs.agent-workflow.paths.controlPlane}  -> .agents/scripts
      #   ${inputs.agent-workflow.paths.learning}      -> .agents/learning
      #   ${inputs.agent-workflow.paths.repoMap}       -> .agents/repo-map
      #   ${inputs.agent-workflow.paths.schemas}       -> .agents/schemas
      #   ${inputs.agent-workflow.paths.orchestration} -> repo-root scripts/agent-*.sh
      #
      # Until that wiring lands, the nixos-config repo keeps running its own
      # local copies (fork-forward: this repo is where v2 is built).
      paths = {
        skills = ./skills;
        orchestration = ./orchestration;
        controlPlane = ./scripts;
        schemas = ./schemas;
        repoMap = ./repo-map;
        learning = ./learning;
      };
    };
}
