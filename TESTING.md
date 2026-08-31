# TESTING.md

How changes to the template or image get verified before they can affect production. The release workflow publishes
only a GitHub release; PR workflows test the changed layer without touching the live Coder deployment.

## Intent

A change to `templates/**` or `images/**` is not trustworthy just because it parses (that is what lint and
`terraform validate` cover — see [CLAUDE.md](CLAUDE.md)). Each PR path must test the artifact it changes without
changing a live template, its backing storage, or a published image tag.

## How it works

`publish.yaml` runs only for a published GitHub release. It still builds the multi-architecture image, publishes it to
the registries, and pushes the live Coder template with that release tag.

PR workflows are scoped directly by changed paths:

- `test-image.yaml` runs for image changes. It delegates the multi-architecture build and private-registry cache to
  the shared image-build workflow, which connects to Tailscale for that registry.
- `test-template.yaml` runs for template changes. It creates a local Coder/Postgres compose deployment, gives Coder
  the test-cluster kubeconfig, publishes the template with the latest released GHCR workspace image, creates a
  workspace, pings its agent three times with a timeout, and verifies SSH by running `env`.

The temporary Coder deployment has no `CODER_ACCESS_URL`, so Coder creates its development tunnel. This is the
workspace agent's route back from Kind; the runner continues to call Coder on localhost and template testing needs
neither Tailscale nor the private registry. Test mode omits the production `/tmp` volume and uses a 2 GiB home volume;
live workspaces retain their production storage. The Compose Coder version matches the live deployment's Helm chart
version and the Postgres version matches the live CloudNativePG cluster's (see `homelab-ops-kubernetes-apps`'s
`apps/subsystems/coder/`) — the Postgres *image* itself is the plain upstream one rather than CloudNativePG's, since
this Compose stack isn't standing in for CloudNativePG, just a same-version Postgres for Coder to talk to. Both
versions are pinned directly in `compose.yaml`'s `image:` lines and picked up by Renovate's built-in `docker-compose`
manager — no repo config needed, and (via the `docker:pinDigests` preset already in force here) the same digest
pinning the Dockerfile's `FROM` line gets.

## Running the template test locally

`test-template.yaml` needs nothing CI has that a laptop doesn't — no secrets, no Tailscale, no private registry. With
`kind`, `docker compose`, `kubectl`, and the `coder` CLI on `PATH`, from the repo root:

```bash
kind create cluster --name coder-template-test
kubectl create namespace coder

kind export kubeconfig --name coder-template-test --kubeconfig /tmp/kind-kubeconfig
cp /tmp/kind-kubeconfig /tmp/coder-kubeconfig
sed -Ei 's#https://127\.0\.0\.1:[0-9]+#https://coder-template-test-control-plane:6443#' /tmp/coder-kubeconfig
chmod 644 /tmp/coder-kubeconfig

CODER_KUBECONFIG=/tmp/coder-kubeconfig docker compose -f .github/compose/compose.yaml up --detach

# once http://localhost:7080/api/v2/buildinfo responds:
docker compose -f .github/compose/compose.yaml exec coder \
  coder server create-admin-user --username ci --email ci@example.invalid --password ci-password
coder login http://localhost:7080 --username ci --password ci-password

coder template push --directory templates/kubernetes/homelab-workspace \
  --var workspace_image=ghcr.io/ppat/coder-workspace:<a-released-tag> --var test_mode=true \
  --name local --yes homelab-workspace-test
coder create local-test --template homelab-workspace-test --no-wait --yes \
  --parameter memory=4 --parameter preferred_nodes='[]' --parameter memory_watchdog_mode=enforce
coder ping --num 3 --timeout 30s local-test
coder ssh local-test -- env
```

Tear down with `docker compose -f .github/compose/compose.yaml down --volumes` and
`kind delete cluster --name coder-template-test`. `compose.yaml` uses Compose's default project-directory-from-file
resolution, so the same commands also work as `docker compose up --detach` etc. from inside `.github/compose/` with
no `-f` needed.

## What each stage confirms

1. **Image build** — an image change exercises both published architectures and the existing private cache through
   the shared image-build workflow.
2. **Template runtime** — a template-only PR applies against fresh Coder, Postgres, and Kubernetes state, using the
   last released GHCR image. The workspace start, agent ping, and SSH command prove the rendered template's runtime
   path rather than merely its Terraform syntax.

## The memory watchdog is the one part with runtime behaviour

Everything else here is declarative and is covered by the stages above. `script-memory-watchdog.sh` decides at runtime whether to kill a process, so it gets two things neither lint nor a template push can provide:

- **Fixtures** — `./templates/kubernetes/homelab-workspace/script-memory-watchdog-test.sh`, also run by the `watchdog` job in `.github/workflows/test-watchdog.yaml`. The suite is built around negative assertions paired with the mutation that must flip them: "it did not kill the agent session" proves nothing unless removing one rule makes it kill the agent session. Two of its own safety properties matter as much as its assertions: `kill` is shadowed by a function throughout, because the fixture pids name real processes in whatever container runs the suite; and every load of the watchdog redirects its stdout emission to a temporary file, with the suite exiting outright if that seam did not take — the real default is the container's own stdout, and a run without the seam has already put fixture kill lines into a live workspace's log stream.
- **A live drill on a disposable `test_mode` workspace**, which has disposable storage and can be wrecked freely. Fixtures cannot answer whether a real process tree classifies correctly, whether a supervisor really does respawn what was killed, or whether the respawned process comes back inside its share (a drift the watchdog should keep policing) or above it (an `oversize` it should report and leave alone). The drill that has been run: a stand-in session root (`exec -a claude bash`, to exercise the shebang branch of the claude-root guard rather than the trivial compiled-binary one) with an over-budget helper that a supervisor respawns, a second helper inside its budget, and a process detached into its own session with `setsid` — the same mechanism Claude Code uses to detach a Bash tool call — larger than both.

Neither replaces the other, and the live one is where every defect that mattered in this component has been found.

### What the most recent drill actually observed

Run 2026-08-21 on a disposable `watchdog-drill` workspace, `enforce` mode, **against the pre-envelope construction** — per-role budgets clamped by `memory.max / 8` and a resting floor, with a circuit breaker that disarmed a role permanently. Everything below is what was observed then and is left as the record. Two things in it no longer exist: `event=disarmed` (the breaker now reports `event=kill-rate ... enforcing=yes` and disarms nothing), and the compressed `breaker window` is now only the window that report is rated over. The kills themselves would still happen — the hog was respawned inside its pinned budget each time and drifted out of it, which is the drift case, not the `oversize` one. It was run with every threshold compressed and wall-clock arithmetic left real (`WATCHDOG_NOW` was never set): dwell 600→20s, age floor 300→45s, kill grace 30→8s, breaker window 3600→180s, sweep cadence ~60→~3s, `WATCHDOG_BUDGET_claudeHelper` pinned 512→100 MiB. The code paths and the arithmetic are the production ones; production *timings* were never waited out, which is what compressing them costs. The synthetic workload was compiled C — no `python3` or `node` exists on `PATH` in a fresh workspace without dotfiles applied, itself worth knowing.

The daemon's own `actions.log` for the drill, re-fetched from Loki afterward and matched byte-for-byte against the pod's local copy:

```text
event=kill sig=TERM pid=<p1> role=claudeHelper id=hog pss_mb=150 budget_mb=100 over_s=22 age_s=68
event=kill sig=KILL pid=<p1> role=claudeHelper id=hog pss_mb=150 budget_mb=100 over_s=31 detail="still over budget 8s after SIGTERM"
event=kill sig=TERM pid=<p2> role=claudeHelper id=hog pss_mb=150 budget_mb=100 over_s=43 age_s=46
event=kill sig=KILL pid=<p2> role=claudeHelper id=hog pss_mb=150 budget_mb=100 over_s=52 detail="still over budget 8s after SIGTERM"
event=disarmed role=claudeHelper reason=kill-loop kills=3 window_s=180 budget_mb=100 detail="a role that has to be killed this often does not have a drift problem, it has a wrong budget; raise WATCHDOG_BUDGET_claudeHelper or accept the size, but this watchdog will not keep restarting it"
```

The two kills are gated by two different rules, not the same one twice: the first fired at `over_s=22` against a 20s dwell — one sweep late, proportional to the ~3s cadence, i.e. dwell-bound. The second's dwell was satisfied around `over_s≈20`, but the kill waited for `age_s` to clear its 45s floor, so `over_s` kept climbing to 43 before it fired — age-bound. A third respawn (not shown above) supplied the kill that tripped the breaker; under the current construction that same kill produces an `event=kill-rate` line and enforcement continues.

`sweep.log` also confirms a dip resets the dwell clock rather than just capping it, in consecutive rows for the same pid:

```text
... over 153981 155052 55 102400 15 ...   <- over_s climbing toward the dwell threshold
...  ok   20861  22020 58 102400  0 ...   <- PSS dropped under budget; over_s reset to 0
```

Equally load-bearing is what `actions.log` does **not** contain: the `setsid`-detached process standing in for a Claude Code Bash tool call — the single largest process in the drill — appears zero times, and neither does the in-budget helper. Both were alive and untouched when the drill ended.

Not exercised by this drill, and not claimed to be: production timings (everything above ran on compressed ones); the VS Code tree half of selection (`extensionHost`/`tsserver`/`fileWatcher`/`ptyHost`) — no VS Code server ran in this disposable pod; `observe` mode's `would-kill`; the global 8-kill-across-roles breaker; and `event=refused`, whose guard is structurally unreachable in normal operation because selection filters protected pids before `signal_pid` is ever called.

### Checking a claim like this against the record

An `event=kill`/`event=oversize` line, unlike the sweep log, does leave the pod (see [DESIGN.md](DESIGN.md#design-tensions-and-decisions)), so a claim like the one above is checkable: `{namespace="coder"} |= "component=memory-watchdog" |~ "event=(kill|would-kill|oversize|refused|kill-rate)"` against Loki finds exactly the six lines quoted above, timestamped and labelled with the `watchdog-drill` pod.

The same query, run over the full retained history, is also what falsifies a different claim: PR [#865](https://github.com/ppat/coder/pull/865) (merged 2026-08-18), which introduced this drill practice, described one run in its body as killing "a drifted 739 MB helper... three times" with the role disarming "on the third kill," and stated "the daemon's own lines from the test workspace are in Loki." Neither `event=kill` nor `event=disarmed` nor the string `739` appears anywhere in the retained record for any workspace at any time before this run. The only kill/disarm lines anywhere near that PR's merge time are on the operator's live workspace at 2026-08-18T01:01–01:08, and the daemon logged its own correction for them at the time: `event=note reason=fixture-leak`, naming fixture pids 41/61 at 1907/1583 MB — the same incident this repo's docs already describe as the fixture suite's stdout seam leaking into production before it was guarded. No `event=kill` or `event=disarmed` line from a workspace named `test` exists in the record at all. `event=budget role=extensionHost budget_mb=1069 pod_share_mb=512 floored=1` — the figures the PR body also cites as drill evidence — is not distinguishing evidence either: every disposable `test_mode` workspace since has printed exactly that line at startup, regardless of whether anything was ever killed, because `floored=1` was a constant at that pod size — the bug PR #881 fixes.

None of this proves the described drill did not happen — a drill run through the fixture harness's required `WATCHDOG_STDOUT_PATH` seam would, correctly, leave nothing in Loki to find, which is indistinguishable in the record from a drill that never ran. What the record supports is narrower than what was claimed: the specific figures and the "verified end to end... in Loki" line cannot be checked, and the only Loki-verifiable kill/disarm evidence tied to that PR's timeframe is the fixture leak, which was not a drill result. The verified account above is offered in its place.

## After merge

Merging an ordinary PR to `main` updates release-please's standing release PR; it does not publish artifacts. Merging that release PR creates the GitHub release, which flips the publish pipeline into live mode. The test-mode pass on the original PR is the actual artifact-release gate.
