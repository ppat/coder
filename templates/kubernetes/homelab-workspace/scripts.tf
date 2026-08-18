# Agent-side scripts. There is no systemd and no supervisor in this pod - PID 1
# is the coder agent - so coder_script is the only thing that can start a daemon
# or run something on a schedule here.

# Starts the memory watchdog, which bounds the standing population of
# restartable helper processes. See script-memory-watchdog.sh for what it does
# and does not attempt, and DESIGN.md for why the acute OOM half of its former
# job is not one a poll loop can do.
#
# setsid --fork detaches the watchdog from the agent's script runner, so this
# resource completes immediately and start_blocks_login stays honest. The
# consequence is that an agent restart without a pod restart leaves the previous
# watchdog running - which is what the script's pid-file guard is for.
resource "coder_script" "memory_watchdog" {
  agent_id           = coder_agent.main.id
  display_name       = "Memory watchdog"
  icon               = "/icon/memory.svg"
  run_on_start       = true
  start_blocks_login = false
  script             = <<-EOT
    set -u
    state_dir="$${HOME}/.local/state/vscode-memory-watchdog"
    mkdir -p "$${state_dir}"
    /usr/bin/setsid --fork /bin/bash /memory-watchdog.sh \
      </dev/null >>"$${state_dir}/boot.log" 2>&1
    echo "memory watchdog started in $${WATCHDOG_MODE:-observe} mode; state in $${state_dir}"
  EOT
}

# Weekly garbage collection of ~/.vscode-server, which grows without bound and
# inflates the dentry/inode slab.
#
# This used to expect $HOME/.local/bin/vscode-server-gc from the operator's
# dotfiles, gated by `[ -x ... ] && ... || true`. That broke on any workspace
# without dotfiles applied - confirmed on the `test` workspace, which reached
# ~11 GB of ~/.vscode-server with dotfiles never applied to it - because the
# guard made "the script isn't there" indistinguishable from "the script ran
# and had nothing to do": both report success on this cron. script-vscode-
# server-gc.sh is template-owned instead: mounted into the pod via
# configmap.tf/deployment.tf like script-agent-startup.sh and
# script-memory-watchdog.sh, so it is guaranteed present whenever this
# resource's cron fires, and invoked directly below with no existence check -
# an actual failure now surfaces as a failed run in the Coder UI instead of
# vanishing into `|| true`.
resource "coder_script" "vscode_server_gc" {
  agent_id     = coder_agent.main.id
  display_name = "vscode-server GC"
  icon         = "/icon/code.svg"
  # Coder's cron is 6-field (seconds first), not the usual 5. Sundays at 04:00.
  cron   = "0 0 4 * * 0"
  script = "/bin/bash /vscode-server-gc.sh"
}
