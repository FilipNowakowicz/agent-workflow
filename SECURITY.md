# Security Policy

This repository publishes workflow code, skills, schemas, and examples for a
self-hosted agent loop. It does not publish live credentials, host secrets, or
operator-specific runtime state.

## Reporting a Vulnerability

Please report security issues privately through GitHub's private vulnerability
reporting flow if it is available for this repository. If that is not available,
open a minimal issue that says a private report is needed, without including
exploit details, credentials, hostnames, or logs that may contain secrets.

Useful reports include:

- a workflow path that could execute untrusted public issue or PR content;
- a way for a model or issue body to grant itself merge authority;
- a credential, token, host secret, or private endpoint accidentally committed
  to this repository;
- a bug in policy/routing/review checks that weakens a documented trust
  boundary.

## Out Of Scope

The public repository cannot support or debug private operator credentials,
live GCP hosts, SSH access, Claude/Codex account state, or downstream consumer
repositories. Please reduce those reports to a repository-local reproduction
before filing.

## Supported Versions

Until the project has tagged releases, only the current `main` branch is
treated as supported.
