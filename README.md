# coder

Terraform templates and container images for [Coder](https://coder.com/) workspaces, running on a personal Kubernetes homelab cluster.

## Contents

- **`templates/kubernetes/homelab-workspace/`** — the Coder/Kubernetes Terraform template that provisions a workspace pod.
- **`images/homelab-workspace/`** — the Ubuntu-based container image that pod runs.

Template and image are versioned and released together; see [DESIGN.md](DESIGN.md) for why. Dependency versions (Terraform providers, image packages, GitHub Actions) are kept current mostly by Renovate.

This repo is the middle of a larger stack: the Coder control plane is deployed separately (from the `homelab-ops-kubernetes-*` repos), and an operator's day-to-day tooling comes from their [dotfiles](../dotfiles) at provision time. See [DESIGN.md](DESIGN.md#where-the-workspace-environment-comes-from) for how the image, template, and those neighbours layer into one workspace environment.

## Docs

- **[DESIGN.md](DESIGN.md)** — why the template and image are built the way they are: trade-offs considered, decisions made, targeted outcomes.
- **[TESTING.md](TESTING.md)** — how to validate a change, including exercising it against the real cluster without touching production workspace data.
- **[CLAUDE.md](CLAUDE.md)** — commands and conventions for working in this repo with Claude Code.
- **[CHANGELOG.md](CHANGELOG.md)** — generated release history (semantic-release).

## Contributing

Commit messages follow Conventional Commits, enforced by commitlint — see [CLAUDE.md](CLAUDE.md#commit-messages) for the allowed scopes. Releases and publishing are fully automated from `main`; see [DESIGN.md](DESIGN.md#template--image-release-together) and [TESTING.md](TESTING.md).
