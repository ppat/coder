locals {
  test_service_commands = [
    "test -f /home/coder/.local/state/dotfiles/applied || { touch /tmp/service-started-too-early; exit 1; }; printf x >> /tmp/service-restarts; sleep 2; exit 1",
    "test -f /home/coder/.local/state/dotfiles/applied || { touch /tmp/service-started-too-early; exit 1; }; touch /tmp/service-steady; exec sleep 300"
  ]
}

# tflint-ignore: terraform_unused_declarations
data "coder_workspace_preset" "test" {
  name        = "test"
  description = "Preset used for testing the homelab-workspace template within github actions ci workflow"
  parameters = {
    (data.coder_parameter.use_existing_home_pvc.name) = false
    (data.coder_parameter.dotfiles_url.name)          = "https://github.com/ppat/dotfiles.git"
    (data.coder_parameter.memory_watchdog_mode.name)  = "enforce"
    (data.coder_parameter.service_commands.name)      = jsonencode(local.test_service_commands)
  }
}
