# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

This repo holds [Coder](https://coder.com/) workspace **templates** (Terraform) and the **container images** those templates provision — it is not an application codebase. There is currently one template/image pair, both named `homelab-workspace`:

- `templates/kubernetes/homelab-workspace/` — Terraform template (`coder/coder` + `hashicorp/kubernetes` providers), deployed to a personal Kubernetes cluster.
- `images/homelab-workspace/Dockerfile` — the Ubuntu-based image the template's pod runs.

Almost all day-to-day change here is dependency bumps (Renovate) or edits to the template/image; there's no application logic, unit tests, or build step in the traditional sense.

**For why these are built this way and how the pieces tie together, see [DESIGN.md](DESIGN.md). This file only covers how to work here.**

## Commands

No package-manager project lives here (`mise.toml` just pins `bun`/`node`/`terraform`/`tflint` tool versions). Local validation is `pre-commit`:

```bash
pre-commit run --all-files        # yamllint, markdownlint, shellcheck, hadolint, commitlint, terraform fmt/validate/tflint
```

Terraform checks scoped to the one template directory:

```bash
cd templates/kubernetes/homelab-workspace
terraform fmt -check
terraform validate
tflint --config=../../../.tflint.hcl
```

CI (`.github/workflows/lint.yaml`) runs the same checks per file-type via reusable workflows in `ppat/github-workflows`, scoped to changed files on PRs, or everything on `workflow_dispatch`/schedule.

There is no local way to build/publish the image or push the Coder template — see [TESTING.md](TESTING.md) for how a change actually gets exercised (including the `test_mode` flow), and the **Release flow** section below for how it ships for real.

## Commit messages

Commitlint (`commitlint.config.js`) enforces Conventional Commits.

- Allowed scopes only: `cli-tools`, `dev-tools`, `deps`, `github-actions`, `release`, `renovate`, `terraform-provider`, `terraform-version`, or no scope. An unlisted scope fails commit-msg validation.
- Body lines ≤120 chars, except `chore(deps)` commits (Renovate generates these verbatim, so that rule is relaxed for them).

## Release flow

`.github/workflows/release.yaml` triggers on changes to `images/homelab-workspace/**`, `templates/**`, or the release workflow/config itself, and on merge to `main`:

1. `semantic-release` (`.releaserc.js`) cuts a version from commit history, updates `CHANGELOG.md`.
2. The workspace image builds for `linux/amd64,linux/arm64` and pushes to the private registry.
3. The Terraform template pushes to the live Coder deployment via `coder template push`, tagged with the released version.

PRs and manual `workflow_dispatch` runs exercise this same pipeline in dry-run/test mode instead of publishing for real — see [TESTING.md](TESTING.md), which is the required reading before touching `templates/**` or `images/**`.

## Where things live

Quick orientation map — for what each piece is *for* and the decisions behind it, see [DESIGN.md](DESIGN.md).

**Template** (`templates/kubernetes/homelab-workspace/`):

| File | Contents |
| --- | --- |
| `terraform.tf` | Provider requirements/versions (Renovate-managed) |
| `main.tf` | `coder_workspace`/`coder_workspace_owner` data sources, shared labels/path locals |
| `parameters.tf` | User-facing `coder_parameter` inputs + sanitization locals |
| `coder-agent.tf` | `coder_agent` resource: startup script, `coder stat` metadata |
| `deployment.tf` / `configmap.tf` | Kubernetes Pod spec, volumes, ConfigMap |
| `env.tf` | `coder_env` resources exposed to the agent |
| `variables.tf` | `workspace_image`, `test_mode` — both supplied by the release workflow |
| `script-agent-startup.sh` / `script-prepare-workspace.sh` | Scripts run on agent/workspace startup |

**Image** (`images/homelab-workspace/Dockerfile`): three build stages — `base` (minimal bootstrap deps) → `system-base` (`unminimize` + full interactive toolset) → final stage (env vars into `/etc/environment`, fixed-UID/GID `coder` user, `USER coder`). All `apt`-touching `RUN` steps use BuildKit cache mounts — match that pattern when adding packages.

**Renovate** (`.github/renovate.json` + `.github/renovate/*.json`): extends shared `ppat/renovate-presets` plus repo-local rules in `exceptions.json`, `image-cli-tools.json`, `template-terraform-provider.json` that set different automerge delays per dependency class.

## Implementation gotchas

Things that look arbitrary in the code but are load-bearing (full reasoning in [DESIGN.md](DESIGN.md)):

- `deployment.tf`'s `system` volume is an `empty_dir`, rebuilt from the image on every pod start — a fix to anything under `/usr`, `/etc`, `/var` must go in the image or the init script, not be treated as a one-time patch.
- The Dockerfile writes shared env vars to `/etc/environment` rather than using `ENV`, because `PATH` needs to be extended by a script running after the image is built, not fixed at build time.
- `parameters.tf`'s `local.validated_*` regex allowlist is the only thing stopping `system_packages`/`preferred_nodes` from injecting shell metacharacters into the init container — any new list-type parameter must go through the same decode-then-validate step.
- Adding a package/tool has three possible homes, and picking the wrong one is a real mistake, not a style choice — route by the rule in [DESIGN.md](DESIGN.md#where-the-workspace-environment-comes-from): universal + stable → image (`Dockerfile`); occasionally-needed + apt-only + too heavy to bake in → the template's `system_packages` parameter; personal, fast-moving, or not an apt package → the operator's dotfiles (a *different* repo — see below), never this one.
- The rootless-Docker feature (`enable_docker` parameter) spans this repo *and* the apps repo, and has non-obvious load-bearing details — read [DESIGN-DIND.md](DESIGN-DIND.md) before touching it. Key traps: (1) the `kubernetes` provider 3.2.1 has **no `host_users` field**, so `hostUsers: false` is set by a Kyverno policy in the apps repo keyed off the `com.coder.workspace.docker-enabled` marker label — renaming that label breaks the contract silently; (2) the docker-data PVC is gated on `enable_docker` but **not** on `start_count` (like the home PVC) so it survives workspace stop — gating it on `start_count` would wipe every pulled image on each stop; (3) docker's plumbing is baked into the image but its *behaviour* is parameter-gated, because the setuid `newuidmap`/`newgidmap` + subuid/subgid can only be set at build time as root; those setuid bits must survive the init container's `rsync` into the `system` volume.

## Neighbouring repos

This repo is only the image+template layer. When a task's real cause is above or below that layer, it lives elsewhere — describe those repos briefly and link, don't reproduce their content (see [DESIGN.md](DESIGN.md#where-the-workspace-environment-comes-from) for how the layers compose):

- **Coder platform** — the control plane these templates are pushed to, deployed to the cluster from [`homelab-ops-kubernetes-apps`](../homelab-ops-kubernetes-apps/apps/subsystems/coder/helm-release-coder.yaml) (Helm release) and [`homelab-ops-kubernetes-clusters`](../homelab-ops-kubernetes-clusters/clusters/homelab/kustomizations/apps-coder.yaml) (Flux Kustomization).
- **Dotfiles** — the operator's per-workspace tooling (brew/mise/aqua), applied at provision time from [`dotfiles`](../dotfiles). Day-to-day tool installs belong here, not in the image or template.

## Working on a template or image change

1. Make the change, run `pre-commit run --all-files` and the scoped `terraform validate`/`tflint` commands above.
2. Follow [TESTING.md](TESTING.md) to exercise it via `test_mode` before merging — merging to `main` publishes to the real template/image with no separate promotion step.
