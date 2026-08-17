# Agent-side scripts. There is no systemd and no supervisor in this pod - PID 1
# is the coder agent - so coder_script is the only thing that can start a daemon
# or run something on a schedule here.

# Starts the memory watchdog. See script-memory-watchdog.sh for why a userspace
# watchdog is the only option, and DESIGN.md for the constraint that forces it.
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
# The split is deliberate: the logic operates on a personal directory and lives
# in the operator's dotfiles repo, while the schedule has to live here because
# coder_script's cron is the only scheduler this pod has. Missing script => no-op,
# so this resource is safe before the dotfiles side lands.
resource "coder_script" "vscode_server_gc" {
  agent_id     = coder_agent.main.id
  display_name = "vscode-server GC"
  icon         = "/icon/code.svg"
  # Coder's cron is 6-field (seconds first), not the usual 5. Sundays at 04:00.
  cron   = "0 0 4 * * 0"
  script = <<-EOT
    set -u
    gc="$${HOME}/.local/bin/vscode-server-gc"
    if [ -x "$${gc}" ]; then
      "$${gc}"
    else
      echo "no $${gc}; skipping"
    fi
  EOT
}
