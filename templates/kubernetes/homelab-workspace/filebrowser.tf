resource "coder_agent" "filebrowser" {
  arch                    = "amd64"
  os                      = "linux"
  api_key_scope           = "no_user_data"
  order                   = 1
  startup_script          = "cd /home/filebrowser && ./filebrowser >/tmp/filebrowser.log 2>&1 &"
  startup_script_behavior = "non-blocking"

  display_apps {
    port_forwarding_helper = false
    ssh_helper             = false
    vscode                 = false
    vscode_insiders        = false
    web_terminal           = false
  }
}

resource "coder_app" "filebrowser" {
  agent_id     = coder_agent.filebrowser.id
  slug         = "files"
  display_name = "Files"
  icon         = "/icon/folder.svg"
  url          = "http://localhost:8080"
  share        = "owner"
  # File Browser emits root-relative URLs and expects its configured base path
  # on inbound requests. Coder path apps strip that path before proxying, so an
  # isolated app subdomain is the only mode that preserves both contracts.
  subdomain = true
  open_in   = "tab"

  healthcheck {
    url       = "http://localhost:8080/health"
    interval  = 5
    threshold = 6
  }
}
