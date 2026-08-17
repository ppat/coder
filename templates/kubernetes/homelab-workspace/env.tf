resource "coder_env" "welcome_message" {
  agent_id = coder_agent.main.id
  name     = "HOMEBREW_PREFIX"
  value    = local.homebrew_directory
}

# The switch that arms the memory watchdog. "observe" measures, publishes
# headroom and logs what it would have done; "enforce" additionally sets
# RLIMIT_DATA ceilings and sheds load.
#
# Set from a mutable workspace parameter rather than hardcoded here, because the
# right value is a per-workspace judgement: the tier thresholds are absolute
# bytes sized for an 8 GiB pod, so the same setting that is right there sits
# permanently near L1 on a 4 GiB one. It defaults to "observe" and should stay
# there until the ceilings and thresholds have been set from the calibration data
# the watchdog collects - too low kills a healthy extension host mid-edit, too
# high makes the mechanism inert.
resource "coder_env" "memory_watchdog_mode" {
  agent_id = coder_agent.main.id
  name     = "WATCHDOG_MODE"
  value    = local.validated_watchdog_mode
}
