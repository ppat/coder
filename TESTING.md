# TESTING.md

How changes to the template or image get verified before they can affect production. There's no separate test suite or staging environment (see [DESIGN.md](DESIGN.md)) — verification is the release pipeline itself, run in a mode that exercises everything a real release would except the parts that would affect the live template or its persistent state.

## Intent

A change to `templates/**` or `images/**` isn't trustworthy just because it parses (that's what lint/`terraform validate` already cover — see [CLAUDE.md](CLAUDE.md)). It's trustworthy once the same pipeline that would ship it has actually built the image and applied the template against the real cluster and provider. The test workflow's job is to make that possible on every PR, automatically, without any risk to the production template or the shared persistent state real workspaces depend on.

## How it works

The publish pipeline (`.github/workflows/publish.yaml`) runs in one of two modes, gated by the event that starts it:

- **Test mode** — automatic on any PR touching `images/**`, `templates/**`, or the publish workflow, and available on demand via manual dispatch.
- **Live mode** — runs only when release-please has published a GitHub release after its release PR is merged.

Both modes run the identical image build and template-push sequence; only the release source and destination differ. Release coordination is separate: `.github/workflows/release.yaml` runs release-please on `main`, creating or updating its release PR. A PR test does not simulate that release step.

## What each stage confirms

1. **Release source** — test mode builds the PR branch or manually dispatched ref, and names the test template with that event's commit SHA. Live mode uses the GitHub release tag created by release-please for both. This keeps a test publish tied to the code under review without pretending that a release exists.
2. **Image build** — the container image is built for every published architecture and pushed to the registry. This is the same build a live release performs, so it confirms the Dockerfile still produces a working image end to end — test mode only changes the tag it is pushed under, not the build itself.
3. **Template push** — the Terraform template is applied against the real Coder deployment and Kubernetes cluster, using the image just built. This confirms the template is actually valid against live provider/cluster state, not just internally consistent. Test mode redirects this push to a separate, clearly-named template rather than the one real workspaces use, and backs it with disposable storage instead of the shared persistent volume — so nothing here can affect an existing workspace no matter what the change does.

Because both publishing stages run for real in test mode — just scoped away from production — a passing PR is a meaningful signal that a live release would also succeed, not a guess based on static checks alone.

## The memory watchdog is the one part with runtime behaviour

Everything else here is declarative and is covered by the stages above. `script-memory-watchdog.sh` decides at runtime whether to kill a process, so it gets two things neither lint nor a template push can provide:

- **Fixtures** — `./templates/kubernetes/homelab-workspace/script-memory-watchdog-test.sh`, also run by the `watchdog` job in `.github/workflows/test.yaml`. The suite is built around negative assertions paired with the mutation that must flip them: "it did not kill the agent session" proves nothing unless removing one rule makes it kill the agent session. Two of its own safety properties matter as much as its assertions: `kill` is shadowed by a function throughout, because the fixture pids name real processes in whatever container runs the suite; and every load of the watchdog redirects its stdout emission to a temporary file, with the suite exiting outright if that seam did not take — the real default is the container's own stdout, and a run without the seam has already put fixture kill lines into a live workspace's log stream.
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
