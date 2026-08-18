resource "coder_env" "welcome_message" {
  agent_id = coder_agent.main.id
  name     = "HOMEBREW_PREFIX"
  value    = local.homebrew_directory
}

# The switch that arms the memory watchdog. "observe" measures and records what
# it would have done; "enforce" kills helpers that have been over budget for ten
# minutes; "enforce-all" adds the two editor roles whose restart the operator can
# see.
#
# Set from a mutable workspace parameter rather than hardcoded here, because it
# is the one control that decides whether the watchdog may signal anything, and
# because turning it off has to be a parameter change rather than a code change
# on a bad day. The budgets themselves are derived from the pod's own memory.max,
# so this value does not have to be reconsidered per pod size.
resource "coder_env" "memory_watchdog_mode" {
  agent_id = coder_agent.main.id
  name     = "WATCHDOG_MODE"
  value    = local.validated_watchdog_mode
}
