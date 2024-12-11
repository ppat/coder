data "coder_parameter" "dotfiles_repo" {
  display_name = "Dotfiles Repository"
  name         = "dotfiles_repository"
  type         = "string"
  icon         = "/icon/personalize.svg"
  default      = "git@github.com:ppat/dotfiles.git"
}
