# TESTING.md

How changes to the template or image get verified before they can affect production. There's no separate test suite or staging environment (see [DESIGN.md](DESIGN.md)) — verification is the release pipeline itself, run in a mode that exercises everything a real release would except the parts that would affect the live template or its persistent state.

## Intent

A change to `templates/**` or `images/**` isn't trustworthy just because it parses (that's what lint/`terraform validate` already cover — see [CLAUDE.md](CLAUDE.md)). It's trustworthy once the same pipeline that would ship it has actually built the image and applied the template against the real cluster and provider. The test workflow's job is to make that possible on every PR, automatically, without any risk to the production template or the shared persistent state real workspaces depend on.

## How it works

The release pipeline (`.github/workflows/release.yaml`) runs in one of two modes, gated by whether it's allowed to publish for real:

- **Dry-run mode** — automatic on any PR touching `images/**`, `templates/**`, or the release config itself, and available on demand via manual dispatch.
- **Live mode** — runs on merge to `main`.

Both modes run the identical sequence of stages; only what each stage is permitted to do at the end differs.

## What each stage confirms

1. **Versioning** — commit history since the last release is parsed to determine what the next version would be. In dry-run this stops short of tagging or publishing; it still confirms the commit history is well-formed enough to produce a valid release.
2. **Image build** — the container image is built for every published architecture and pushed to the registry. This is the same build a live release performs, so it confirms the Dockerfile still produces a working image end to end — dry-run only changes the tag it's pushed under, not the build itself.
3. **Template push** — the Terraform template is applied against the real Coder deployment and Kubernetes cluster, using the image just built. This confirms the template is actually valid against live provider/cluster state, not just internally consistent. Dry-run redirects this push to a separate, clearly-named template rather than the one real workspaces use, and backs it with disposable storage instead of the shared persistent volume — so nothing here can affect an existing workspace no matter what the change does.

Because all three stages run for real in dry-run — just scoped away from production — a passing PR is a meaningful signal that a live release would also succeed, not a guess based on static checks alone.

## The memory watchdog is the one part with runtime behaviour

Everything else here is declarative and is covered by the stages above. `script-memory-watchdog.sh` decides at runtime whether to kill a process, so it gets two things neither lint nor a template push can provide:

- **Fixtures** — `./templates/kubernetes/homelab-workspace/script-memory-watchdog-test.sh`, also run by the `watchdog` job in `.github/workflows/test.yaml`. The suite is built around negative assertions paired with the mutation that must flip them: "it did not kill the agent session" proves nothing unless removing one rule makes it kill the agent session. Two of its own safety properties matter as much as its assertions: `kill` is shadowed by a function throughout, because the fixture pids name real processes in whatever container runs the suite; and every load of the watchdog redirects its stdout emission to a temporary file, with the suite exiting outright if that seam did not take — the real default is the container's own stdout, and a run without the seam has already put fixture kill lines into a live workspace's log stream.
- **A live drill on a disposable `test_mode` workspace**, which has disposable storage and can be wrecked freely. Fixtures cannot answer whether a real process tree classifies correctly, whether a supervisor really does respawn what was killed, or whether the respawned process comes back inside its share (a drift the watchdog should keep policing) or above it (an `oversize` it should report and leave alone). The drill that has been run: a stand-in session root (`exec -a claude bash`, to exercise the shebang branch of the claude-root guard rather than the trivial compiled-binary one) with an over-budget helper that a supervisor respawns, a second helper inside its budget, and a process detached into its own session with `setsid` — the same mechanism Claude Code uses to detach a Bash tool call — larger than both.

Neither replaces the other, and the live one is where every defect that mattered in this component has been found.

### What the most recent drill actually observed

Run 2026-08-22 on the disposable `test` workspace, 4 GiB pod, against the envelope construction (`2048 MiB`, fixed shares,
`event=kill-rate ... enforcing=yes` in place of the old permanent disarm). Thresholds were compressed and wall-clock
arithmetic left real (`WATCHDOG_NOW` was never set): dwell 600->15s, age floor 300->15s, kill grace 30->8s, sweep cadence
~60->~3s, `WATCHDOG_BUDGET_claudeHelper` pinned 512->100 MiB, `WATCHDOG_SWEEP_LOG_FLOOR` 32 MiB->0 so that every process
carried its guard rule into `sweep.log`. Every other number - the seven envelope shares, the arithmetic, the code paths -
was the production one. Production *timings* were again never waited out, which is what compressing them costs.

The synthetic workload was compiled C driven entirely by environment variables, so that `argv` was free to be spoofed;
there is still no `python3` and no `node` on `PATH` in a fresh workspace without dotfiles. A stand-in server tree was
built out of paths alone - `~/.vscode-server/cli/servers/Stable-.../server/node` as a spoofed `argv[0]`, with
`out/server-main.js` and `--type=extensionHost` as real argv elements - which is enough, because selection keys on
`argv[0]`'s path and on whole argv elements and on nothing else.

What the daemon reported, all of it also re-fetched from Loki afterwards:

```text
event=oversize pid=<a> role=treeHelper id=acme.toml-1.2.3/server pss_mb=400 budget_mb=320 over_s=16 age_s=16 detail="never observed inside its share since it started; ..."
event=oversize pid=<b> role=claudeHelper id=hog pss_mb=150 budget_mb=100 over_s=16 age_s=16 detail="never observed inside its share since it started; ..."
event=kill sig=TERM pid=<c> role=treeHelper id=beta.lang-0.1/server pss_mb=430 budget_mb=320 over_s=16 age_s=38
event=kill sig=TERM pid=<d> role=claudeHelper id=hog pss_mb=160 budget_mb=100 over_s=16 age_s=38
event=kill sig=KILL pid=<d> role=claudeHelper id=hog pss_mb=160 budget_mb=100 over_s=25 detail="still over budget 8s after SIGTERM"
event=kill-rate role=claudeHelper kills=3 window_s=600 budget_mb=100 enforcing=yes detail="this role is being recycled often enough ..."
event=kill-rate role=all kills=9 window_s=600 enforcing=yes detail="kills across several roles in one window; ..."
```

The `oversize`/`drift` split is the point, and both halves are positive results rather than absences. `<a>` and `<b>`
were born above their shares and stayed there: reported every dwell period for the whole run, never signalled, alive at
the end. `<c>` and `<d>` were born inside their shares, were observed fitting past the age floor, then grew out - and
were killed. `<d>` ignored `SIGTERM` on purpose, so the `TERM`->`KILL` escalation ran; each respawn was seen fitting
again and re-armed, which is what shows the classification is keyed per `pid:starttime` rather than per role. The
kill-rate line fired at three kills in a role and again at nine across roles, and enforcement carried on after both -
a later respawn was still killed.

Equally load-bearing is what `actions.log` does **not** contain. None of these appear in it even once, and every one of
them shows up in `sweep.log` as a row that was seen and passed over, which is what separates "spared" from "invisible":

| process | PSS | why it was spared | `guard` |
| --- | --- | --- | --- |
| a `setsid` process in its own session, the largest in the drill | 200 MB | session-boundary walk | `-` |
| a helper comfortably inside its share | 60 MB | under budget | `-` |
| an unrecognised **direct child of the server root** | 200 MB | `is_server_fork`, so role `other` | `-` |
| the two `claude` session roots | - | `argv[0]` basename | `argv0` |
| the coder agent, and `tmux` | 28-53 MB | `comm` | `comm` |
| pid 1 | 28 MB | `pid1` | `pid1` |
| the watchdog itself | 1.7 MB | `self` | `self` |

A second run in `observe` mode, same thresholds, produced `event=would-kill armed=no` for a freshly-born drifter and no
signal of any kind; the process was still alive well past its dwell.

Not exercised by this drill, and not claimed to be: production timings (everything above ran on compressed ones); a real
VS Code server tree, as opposed to one assembled from paths; `event=refused`, whose guard is structurally unreachable in
normal operation because selection filters protected pids before `signal_pid` is ever called; and the `payload` and
`watchdog-*` guard rules, which nothing in a bare disposable pod triggers.

### Checking a claim like this against the record

An `event=kill`/`event=oversize` line, unlike the sweep log, does leave the pod (see [DESIGN.md](DESIGN.md#design-tensions-and-decisions)), so a claim like the one above is checkable: `{namespace="coder"} |= "component=memory-watchdog" |~ "event=(kill|would-kill|oversize|refused|kill-rate)"` against Loki finds every line quoted above, timestamped and labelled with the disposable pod that produced it — 11 `event=kill`, 34 `event=oversize` and 4 `event=kill-rate` lines for the run of 2026-08-22, and not one `sweep.log` row, because those stay in the pod by design and a test asserts that they do.

The same query, run over the full retained history, is also what falsifies a different claim: PR [#865](https://github.com/ppat/coder/pull/865) (merged 2026-08-18), which introduced this drill practice, described one run in its body as killing "a drifted 739 MB helper... three times" with the role disarming "on the third kill," and stated "the daemon's own lines from the test workspace are in Loki." Neither `event=kill` nor `event=disarmed` nor the string `739` appears anywhere in the retained record for any workspace at any time before this run. The only kill/disarm lines anywhere near that PR's merge time are on the operator's live workspace at 2026-08-18T01:01–01:08, and the daemon logged its own correction for them at the time: `event=note reason=fixture-leak`, naming fixture pids 41/61 at 1907/1583 MB — the same incident this repo's docs already describe as the fixture suite's stdout seam leaking into production before it was guarded. No `event=kill` or `event=disarmed` line from a workspace named `test` exists in the record at all. `event=budget role=extensionHost budget_mb=1069 pod_share_mb=512 floored=1` — the figures the PR body also cites as drill evidence — is not distinguishing evidence either: every disposable `test_mode` workspace since has printed exactly that line at startup, regardless of whether anything was ever killed, because `floored=1` was a constant at that pod size — the bug PR #881 fixes.

None of this proves the described drill did not happen — a drill run through the fixture harness's required `WATCHDOG_STDOUT_PATH` seam would, correctly, leave nothing in Loki to find, which is indistinguishable in the record from a drill that never ran. What the record supports is narrower than what was claimed: the specific figures and the "verified end to end... in Loki" line cannot be checked, and the only Loki-verifiable kill/disarm evidence tied to that PR's timeframe is the fixture leak, which was not a drill result. The verified account above is offered in its place.

## After merge

Merging to `main` is what flips the pipeline into live mode — there's no separate promotion step afterward. The dry-run pass on the PR is the actual release gate.
