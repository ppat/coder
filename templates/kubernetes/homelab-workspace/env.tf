resource "coder_env" "welcome_message" {
  agent_id = coder_agent.main.id
  name     = "HOMEBREW_PREFIX"
  value    = local.homebrew_directory
}

# The switch that arms the memory watchdog. "observe" measures, publishes
# headroom and logs what it would have done; "enforce" additionally sets
# RLIMIT_DATA ceilings and sheds load.
#
# Deliberately left at "observe". The ceilings and tier thresholds in
# script-memory-watchdog.sh were derived from role and an 8 GiB budget, not from
# measurement - too low kills a healthy extension host mid-edit, too high makes
# the mechanism inert. Flip this only once the numbers have been set from the
# calibration data the watchdog is collecting.
resource "coder_env" "memory_watchdog_mode" {
  agent_id = coder_agent.main.id
  name     = "WATCHDOG_MODE"
  value    = "observe"
}
