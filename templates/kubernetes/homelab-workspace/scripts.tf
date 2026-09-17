# Agent-side scripts. PID 1 remains the Coder agent. Supervisor manages only the
# user-defined services started after dotfiles; scheduled template work remains
# a coder_script responsibility.

# Dotfiles are personal state layered over the template, so applying them is
# deliberately non-blocking: a broken or unavailable repository must remain a
# visible script failure without withholding SSH access to repair the workspace.
# The external script starts Supervisor only after Chezmoi succeeds, making this
# one script the ordering boundary instead of racing two run-on-start scripts.
resource "coder_script" "dotfiles" {
  agent_id           = coder_agent.main.id
  display_name       = "Apply dotfiles"
  icon               = "/icon/terminal.svg"
  run_on_start       = true
  start_blocks_login = false
  script             = "/bin/bash /scripts/script-dotfiles.sh"
}

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
  script             = "/bin/bash /scripts/script-memory-watchdog-start.sh"
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
  script = "/bin/bash /scripts/script-vscode-server-gc.sh"
}

resource "coder_script" "supervised_services" {
  agent_id           = coder_agent.main.id
  display_name       = "Supervised Services"
  icon               = "/icon/terminal.svg"
  run_on_start       = true
  start_blocks_login = false
  script             = "/bin/bash /scripts/script-start-services.sh"
}
