#!/bin/bash
set -eo pipefail


wipe_tmp() {
  # /tmp is a per-Pod volume (see deployment.tf), not per-container, so it
  # survives a container restart within a live Pod even though it never used
  # to: the previous /tmp was part of the container's writable overlay, which
  # a fresh container instance always got a clean copy of for free. This
  # restores that property explicitly. It runs before anything else so
  # nothing has written into /tmp yet this boot, and pipefail/errexit above
  # mean a failure here aborts this blocking startup script rather than
  # leaving stale scratch space to accumulate silently - a failed wipe shows
  # up as a failed agent startup script in the Coder UI, not as a slow leak.
  echo "Wiping /tmp..."
  find /tmp -mindepth 1 -delete
}

main() {
  wipe_tmp
  if [[ ! -s ~/.bashrc ]]; then
    echo "Setting up starter bash rc scripts from /etc/skel..."
    cp /etc/skel/.bashrc ~/.bashrc
    cp /etc/skel/.profile ~/.profile
    echo 'set -o allexport; source /etc/environment; set +o allexport' >> ~/.bashrc
    echo '------------------------------------------------------------'
  fi
  echo 'Done'
}

main
