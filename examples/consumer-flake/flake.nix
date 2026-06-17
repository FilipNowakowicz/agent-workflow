{
  description = "Example consumer repo pinning agent-workflow as a flake input";

  # Pinning agent-workflow here gives you a tracked, reproducible version in
  # flake.lock (the same way you'd pin nixpkgs), and lets other Nix code in
  # your repo reference inputs.agent-workflow.paths.* as plain Nix paths.
  # It does NOT install anything by itself — see README.md in this directory
  # for the install step.
  inputs.agent-workflow.url = "github:FilipNowakowicz/agent-workflow";

  outputs =
    { self, agent-workflow }:
    {
      # Re-exporting agent-workflow's paths is optional; it's useful if you
      # want other flake outputs in this repo (a devShell, a check) to
      # reference the control-plane source tree without re-deriving it.
      agentWorkflowPaths = agent-workflow.paths;
    };
}
