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

A separate workflow, `.github/workflows/test.yaml`, runs the one thing here that's a test rather than a linter: its `watchdog` job runs `script-memory-watchdog-test.sh` and fails the build on a failed assertion. It's repo-local rather than a reusable workflow because `ppat/github-workflows` has nothing for "execute a test script", and the suite needs only bash and a writable `TMPDIR`:

```bash
./templates/kubernetes/homelab-workspace/script-memory-watchdog-test.sh
```

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
| `scripts.tf` | `coder_script` resources — the memory watchdog daemon and the weekly `vscode-server` GC schedule |
| `variables.tf` | `workspace_image`, `test_mode` — both supplied by the release workflow |
| `script-agent-startup.sh` / `script-prepare-workspace.sh` | Scripts run on agent/workspace startup |
| `script-container-entrypoint.sh` | The workspace container's `command`. Wipes `/tmp` and `exec`s Coder's generated `/workspace-init.sh` — the wipe must precede the agent, see the gotcha below |
| `script-memory-watchdog.sh` | Userspace memory watchdog — see [DESIGN.md](DESIGN.md#design-tensions-and-decisions). It bounds the **standing population of restartable helpers** (per-role PSS budgets, ten-minute dwell, per-role circuit breaker) and records every per-process sweep. It does **not** try to prevent an acute OOM. `memory_watchdog_mode` selects `observe` / `enforce` (helpers — the default) / `enforce-all` (helpers + editor) |
| `script-memory-watchdog-test.sh` | Fixture tests for the watchdog's arithmetic, process selection, budgets, dwell and circuit breaker. Run by hand (`./script-memory-watchdog-test.sh`) and by the `watchdog` job in `.github/workflows/test.yaml`. `kill` is shadowed by a function throughout — the fixture pids are real pids in whatever container runs the suite |
| `script-vscode-server-gc.sh` | Weekly GC of `~/.vscode-server` (interrupted downloads, superseded server versions/extensions, orphaned CLI binaries — see the script's own header for the exact signal per class, and the `coder_script.vscode_server_gc` comment in `scripts.tf` for why it's template-owned rather than dotfiles-owned) |

**Image** (`images/homelab-workspace/Dockerfile`): three build stages — `base` (minimal bootstrap deps) → `system-base` (`unminimize` + full interactive toolset) → final stage (env vars into `/etc/environment`, fixed-UID/GID `coder` user, `USER coder`). All `apt`-touching `RUN` steps use BuildKit cache mounts — match that pattern when adding packages.

**Renovate** (`.github/renovate.json` + `.github/renovate/*.json`): extends shared `ppat/renovate-presets` plus repo-local rules in `exceptions.json`, `image-cli-tools.json`, `template-terraform-provider.json` that set different automerge delays per dependency class.

## Implementation gotchas

Things that look arbitrary in the code but are load-bearing (full reasoning in [DESIGN.md](DESIGN.md)):

- `deployment.tf`'s `system` volume is an `empty_dir`, rebuilt from the image on every pod start — a fix to anything under `/usr`, `/etc`, `/var` must go in the image or the init script, not be treated as a one-time patch.
- The Dockerfile writes shared env vars to `/etc/environment` rather than using `ENV`, because `PATH` needs to be extended by a script running after the image is built, not fixed at build time.
- `parameters.tf`'s `local.validated_*` allowlist is the only thing stopping `system_packages`/`preferred_nodes` from injecting shell metacharacters into the init container — any new parameter whose value reaches a shell must go through the same validate-then-use step.
- `script-memory-watchdog.sh` computes headroom as `memory.max − U`, where `U` sums only the *unreclaimable* fields of `memory.stat` (`anon`, `shmem`, `unevictable`, `slab_unreclaimable`, `kernel_stack`, `pagetables`, `sec_pagetables`, `percpu`, `sock`). Do not "simplify" it to `memory.current` or to `memory.stat`'s `kernel` roll-up: on the live pod those read 96% and 42% of the limit while true `U` is 28%. Nothing acts on this number any more — it is pod-level context for the per-process rows and the honest figure published in the workspace UI.
- **The watchdog is a drift policer, not an OOM preventer, and the difference is measured.** The graded L1–L4 shedding ladder that used to be here was removed, not tuned: the recorded kills are 70–220 MB/s spikes that go from idle to dead inside a minute, a live reproduction climbed the ladder correctly and logged `no-candidates` because the runaway was not in the tree it managed, and the entire editor tree it could shed is ~0.7 GiB — five seconds of that growth. Before re-adding anything reactive, establish that a poll loop can see the event at all. What the loop *is* good at is MB-per-minute growth in the standing population, which is what it now does.
- **Budgets are per role, in PSS, and never below a role's measured *resting* size — not its fresh size.** Fresh tree: extension host 471 MB PSS, serverMain 160 MB, ptyHost 36 MB, file watcher 34 MB. Resting tree (reconnected, idle, 8 GiB pod): extension host **713 MB**, file watcher 88 MB, language server 54 MB, tree total 1093 MB. A uniform 512 MB budget would sit 40 MB above where the extension host *starts* and 200 MB below where it *lives*, which is the same class of defect as the earlier `RLIMIT_DATA` ceiling that landed below what an idle file watcher already held — "calibrated against fresh, deployed against resting" has now appeared twice in this design, so `RESTING_ROLE` holds the resting figures and nothing else. Each budget is `max(min(role budget, memory.max / 8), resting × 1.5)`; on the 8 GiB pod that makes the extension host 1069 MiB rather than the 1024 MiB share, and the derivation records which budgets the floor lifted (`floored=1`), because that means the pod is too small to bound the role at its intended share. The tests assert the *property* — no budget at or below resting, at any pod size — rather than the arithmetic. Override one role with `WATCHDOG_BUDGET_<role>`; PSS (`smaps_rollup`) is the comparison, not RSS and not `VmData`.
- **A kill needs ten minutes of continuous over-budget dwell, and three kills of one role inside an hour disarm that role.** The dwell is what separates drift from load — a language server that balloons while indexing and hands the memory back must survive. The breaker is what stops the failure that would make this actively harmful: kill the extension host → VS Code restarts it → it reloads every extension → it exceeds again → kill, a loop that arrives looking exactly like the watchdog working. It disarms and reports rather than widening its own budget, because a mechanism that raises the limit it is enforcing has stopped enforcing.
- **The watchdog decides what is a VS Code process by executable path — `argv[0]` under `~/.vscode-server/` — never by whether something "is node".** A provisioned workspace has two unrelated node installations: VS Code's bundled one under `~/.vscode-server/cli/servers/Stable-<commit>/server/`, and mise's on `PATH`, which is what repo tooling and the operator's agent sessions run on. (There is no `/usr/bin/node`, and nothing named `node` on `PATH` at all without dotfiles.) `comm` is `MainThread` for every node process in a real tree, never `node`, because V8 renames its main thread; nothing may key off it. `script-memory-watchdog-test.sh` asserts this three ways, each paired with the mutation that flips it.
- **Helpers spawned by an agent session are the second policed population, and the walk that finds them stops at two boundaries: a shell, and a change of session id.** MCP servers live nowhere near `~/.vscode-server`, so the tree-scoped selection could not see them — the largest single offender ever measured was 1.66 GB of python. The session rule is measured, not assumed: on the live workspace a session root has `sid` = its login shell's session, while every Bash tool call has `pgid == sid == its own pid`, because Claude Code detaches each one. That is what keeps an in-flight build out of the policed set even when the tool call's shell has exec'd itself away, which the shell test alone would miss. If Claude Code ever stops detaching, the walk polices *nothing* rather than the wrong thing, and the visibility warning in `actions.log` says so.
- **Identity guards are absolute; the two positional rules are not, and the distinction is deliberate.** `pid 1`, the coder agent, tmux, `claude` session roots, agent payloads and the watchdog's own kin may never be signalled by anything. The ptyHost subtree and "does not run VS Code's own binary" bound the *editor* selection only, so that an MCP server is policed the same whether its session was started with `coder ssh` or in a VS Code terminal — sparing one set because of which terminal it came from would make the mechanism miss half its cases silently. Everything the ptyHost rule genuinely protects (shells, multiplexers, sessions, tool calls) is still covered by identity guards and by the shell/session boundaries.
- **The never-signal guards match `comm`, `argv[0]`'s basename, and whole path segments of argv elements — never a substring of the joined command line.** Loose substrings over-matched twice: `*/claude*` protected an unrelated process because a scratchpad path contained `/claude`, and `*memory-watchdog*` protected *every* process in a test harness because the harness's own directory path contained it, leaving two full runs green while asserting nothing. The watchdog's own identity is structural — its pid, ancestors and descendants — rather than a name at all. Each guard records which rule claimed a process, and the tests assert every rule is individually reachable; a guard nothing can trigger is untested, not correct.
- **The per-process sweep log is a deliverable, not decoration.** `~/.local/state/vscode-memory-watchdog/sweep.log` (plus `sweep.latest`, `summary`, `headroom`, `top`, `calibration.csv`, `actions.log`) records every policed process and every unmanaged one above 32 MB, with a stable identity breadcrumb (an MCP server's module, not `python3`) and argv secrets redacted at the point of writing. The previous version computed this table every cycle and threw it away, which is why every post-mortem in this investigation was unanswerable.
- **Action lines also go to `/proc/1/fd/1`, which is the container's stdout, because PID 1 here is the coder agent.** That is the only route out of this pod — the cluster's log agent tails container stdout and nothing else — and it needs no configuration anywhere: the lines land in Loki labelled by namespace, pod and container. **Only actions** take that route (kills, refusals, disarms, the budgets in force, one census line an hour); the sweep stays local, and a test asserts that it does, because dozens of rows a minute do not belong in a log pipeline. Lines are logfmt starting with `component=memory-watchdog` so `|= "component=memory-watchdog" | logfmt` works against a very chatty stream without adding a stream label, free text is quoted into `detail=` by `record_action` rather than at call sites, and the write is best-effort — one failure disables the path, logs why once, and nothing else changes.
- **A test fixture that can write to `/proc/1/fd/1` writes into production telemetry.** This happened: the first run of the suite after the stdout path was added — before the harness set the seam — put fixture `event=kill role=extensionHost pss_mb=1907` lines into the live workspace's container log and thus into Loki, describing kills that never occurred in the exact format a post-mortem would trust. `load_watchdog` now sets `WATCHDOG_STDOUT_PATH` and the suite **exits** rather than continuing if the seam did not take. Any future test seam that fans out to a real sink deserves the same treatment.
- Watchdog state keys — the dwell clock and the SIGTERM/SIGKILL escalation — are keyed on `pid:starttime`, never on pid alone. A recycled pid must not inherit another process's history and be killed for it.
- `parameters.tf`'s `memory_watchdog_mode` also goes through the `local.validated_*` treatment: Coder constrains the value server-side, but it is the single switch deciding whether the watchdog may signal processes, so an unrecognised value falls back to the inert `observe` rather than being passed through.
- Adding a package/tool has three possible homes, and picking the wrong one is a real mistake, not a style choice — route by the rule in [DESIGN.md](DESIGN.md#where-the-workspace-environment-comes-from): universal + stable → image (`Dockerfile`); occasionally-needed + apt-only + too heavy to bake in → the template's `system_packages` parameter; personal, fast-moving, or not an apt package → the operator's dotfiles (a *different* repo — see below), never this one.
- `deployment.tf` mounts `/tmp` on its own ephemeral Longhorn volume, not the node's root filesystem and not the NFS-backed home PVC - see [DESIGN.md](DESIGN.md#design-tensions-and-decisions) for why both of those are wrong for it. Its lifecycle is per-Pod, the same as the `system` volume, so it is *not* wiped by a container-only restart within a live Pod - `script-container-entrypoint.sh` wipes it explicitly on every container start instead. Anything relying on `/tmp` persisting across a container restart was already wrong before this (the same was true for free when it was the container's writable overlay).
- **The `/tmp` wipe belongs in the container entrypoint and nowhere later - this is a fixed regression, not a style preference.** The workspace container's `command` is `script-container-entrypoint.sh`, which wipes `/tmp` and then `exec`s Coder's generated `/workspace-init.sh`. That bootstrap unpacks the agent CLI into a per-boot `mktemp` directory under `/tmp`, chdirs into it, appends it to the PATH of every session and script the agent runs, and only then runs the agent startup script - so wiping `/tmp` from `script-agent-startup.sh` deletes the CLI the agent installed seconds earlier and every `coder stat` metadata panel reports `coder: command not found`. Do not "fix" a future collision here with an exclusion list: the agent's `/tmp` paths are version-dependent and not consistently prefixed (v2.35.3 owns `coder.XXXXXX/`, `coder-agent.sock`, `coder-agent*.log`, `coder-script-data/`, `coder-screen/` *and* `boundary-audit.sock`), so an allowlist rots silently. `script-agent-startup.sh` asserts the CLI resolves and runs, which is what makes a recurrence loud.
- A `coder_script` in `scripts.tf` must never gate its actual work behind `[ -x <path> ] && ... || true` (or equivalent) when `<path>` is supplied by something outside the template, e.g. a dotfiles-installed binary. That guard makes "the payload isn't there" indistinguishable from "the payload ran and had nothing to do" — both report success on the schedule's weekly cron. This happened: `vscode_server_gc` was originally written that way, expecting `$HOME/.local/bin/vscode-server-gc` from dotfiles, and would have silently no-opped forever on any workspace dotfiles hadn't been applied to (confirmed on the `test` workspace, which reached ~11 GB of `~/.vscode-server` with dotfiles never applied). Fixed by making `script-vscode-server-gc.sh` a template-owned script mounted via `configmap.tf`/`deployment.tf`, so `scripts.tf` invokes it directly and an actual failure now surfaces as a failed run in the Coder UI instead of vanishing into `|| true`.
- `deployment.tf`'s Deployment `metadata.name` (`local.workload_name` in `main.tf`) is not cosmetic: the cluster's Prometheus resolves pod → ReplicaSet → Deployment via an existing `kube_pod_owner` recording rule and exposes the result as a `workload` label with no other join needed, so whatever this Deployment is named *is* the identity CPU/memory/PSI/OOM metrics get attributed to. Don't revert it to an opaque identifier (e.g. the workspace UUID) without re-breaking that attribution — see [DESIGN.md](DESIGN.md#design-tensions-and-decisions).

## Neighbouring repos

This repo is only the image+template layer. When a task's real cause is above or below that layer, it lives elsewhere — describe those repos briefly and link, don't reproduce their content (see [DESIGN.md](DESIGN.md#where-the-workspace-environment-comes-from) for how the layers compose):

- **Coder platform** — the control plane these templates are pushed to, deployed to the cluster from [`homelab-ops-kubernetes-apps`](../homelab-ops-kubernetes-apps/apps/subsystems/coder/helm-release-coder.yaml) (Helm release) and [`homelab-ops-kubernetes-clusters`](../homelab-ops-kubernetes-clusters/clusters/homelab/kustomizations/apps-coder.yaml) (Flux Kustomization).
- **Dotfiles** — the operator's per-workspace tooling (brew/mise/aqua), applied at provision time from [`dotfiles`](../dotfiles). Day-to-day tool installs belong here, not in the image or template.

## Working on a template or image change

1. Make the change, run `pre-commit run --all-files` and the scoped `terraform validate`/`tflint` commands above.
2. Follow [TESTING.md](TESTING.md) to exercise it via `test_mode` before merging — merging to `main` publishes to the real template/image with no separate promotion step.
