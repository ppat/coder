FROM ubuntu:noble@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea AS base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH

# Place all __pycache__ and *.pyc within a location outside of /usr or /opt,
# - so that it can be easily cleared by the user (as needed)
# - so that they need not be built into the image
ENV PYTHONPYCACHEPREFIX=/var/cache/python
RUN --mount=type=cache,target=/var/cache/apt,id=cache-apt-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/var/cache/debconf,id=cache-debconf-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/var/lib/apt,id=lib-apt-${TARGETARCH},sharing=locked \
    --mount=type=tmpfs,target=/var/cache/python \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    # enable caching of apt packages
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
    # minimum requirements for base image (for supporting builds of subsequent stages)
    apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends \
        bash \
        ca-certificates \
        coreutils \
        curl \
        jq \
        locales \
        openssl \
        unzip \
        && \
    # generate locales (needed for many applications, specially python)
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    echo "LANG=en_US.UTF-8" > /etc/locale.conf && \
    LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 locale-gen en_US.UTF-8 && \
    # Clean pycache created during apt-get install (as apt stills retains some crud in spite of PYTHONPYCACHEPREFIX)
    find /usr -name __pycache__ -exec rm -rf {} +

# ========================================================================================================
FROM base AS system-base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH

ENV PYTHONPYCACHEPREFIX=/var/cache/python
RUN --mount=type=cache,target=/var/cache/apt,id=cache-apt-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/var/cache/debconf,id=cache-debconf-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/var/lib/apt,id=lib-apt-${TARGETARCH},sharing=locked \
    --mount=type=tmpfs,target=/var/cache/python \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    # need unminimized variants of tools in coder workspace image
    apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends man-db unminimize && \
    sed -i 's|xargs dpkg -S|xargs -r dpkg -S|g' /usr/bin/unminimize && \
    echo -e 'y\ny' | /usr/bin/unminimize && \
    # install system packages needed within coder workspace image
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -yq \
      apt-file \
      apt-transport-https \
      apt-utils \
      bash-completion \
      bc \
      binutils \
      bsdextrautils \
      dnsutils \
      file \
      fontconfig \
      gettext \
      git \
      htop \
      inetutils-tools \
      iotop \
      iputils-ping \
      iputils-tracepath \
      ldap-utils \
      less \
      libarchive-tools \
      libheif-dev \
      libraw-dev \
      lsof \
      lz4 \
      make \
      nano \
      netcat-openbsd \
      net-tools \
      openssh-client \
      pipx \
      pkg-config \
      postgresql-client \
      procps \
      psmisc \
      pv \
      python-is-python3 \
      python3 \
      python3-pip \
      python3-venv \
      rsync \
      screen \
      sshpass \
      ssh-askpass \
      strace \
      sudo \
      sysstat \
      tmux \
      traceroute \
      tree \
      tzdata \
      vim \
      wget \
      xz-utils \
      zip \
      zstd \
      && \
    # Clean pycache created during apt-get install (as apt stills retains some crud in spite of PYTHONPYCACHEPREFIX)
    find /usr -name __pycache__ -exec rm -rf {} +

# Docker CLI only (no docker-ce/containerd.io) - this workspace pod is unprivileged by design and has no
# local dockerd; the CLI talks to a remote daemon over `DOCKER_HOST=ssh://...` (wired up by the Terraform
# template). A local docker group/sudo rule would authorize access to a local socket that doesn't exist
# here - don't add one. buildx/compose are client-side plugins, so a remote daemon doesn't provide them;
# the apt packages install to /usr/libexec/docker/cli-plugins, one of the docker CLI's default plugin
# search paths, so `docker buildx`/`docker compose` resolve without extra configuration.
#
# docker-buildx and docker-compose are UPX-compressed in place afterwards (measured: to ~30% of their
# installed size each). /usr/bin/docker itself is deliberately left uncompressed: UPX refuses to pack it
# ("CantPackException: bad e_shstrtab", reproduced on UPX 4.2.2 and 5.2.0) because, unlike the other two,
# it's dynamically-linked/PIE rather than statically linked; `strip`-ing it first works around that but
# also drops its debug symbols, a separate trade-off not applied here without being asked for. UPX comes
# from its own GitHub release rather than the `upx-ucl` apt package, so the tool and its dependency
# closure never land in this layer and the version tracks upstream rather than whatever Ubuntu froze; it
# is downloaded, used, and removed within this same RUN, into the tmpfs-mounted /tmp so it can't leave a
# trace even if the explicit cleanup below were ever dropped. No sha256 pin on that download: the HTTPS
# GET already authenticates via GitHub's TLS certificate, and a hand-computed checksum has no automated
# way to be recomputed on a Renovate-driven UPX_VERSION bump, so it would just go stale and turn the next
# bump into a guaranteed broken build - same reasoning (and same operator) as the docker-host VM's
# cloud-init in homelab-ops-kubernetes-experiments, which omits checksums on its own
# download.docker.com/github.com fetches for this exact reason. Compressing these apt-installed binaries
# in place means `dpkg -V` will report them as modified - that's expected, not corruption. UPX-packed
# binaries also decompress into memory on every exec, a small startup-time/RSS cost that's a non-issue for
# an interactively-invoked CLI.
# renovate: datasource=github-releases depName=upx/upx
ARG UPX_VERSION="5.2.0"
RUN --mount=type=cache,target=/var/cache/apt,id=cache-apt-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/var/cache/debconf,id=cache-debconf-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/var/lib/apt,id=lib-apt-${TARGETARCH},sharing=locked \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
      > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -yq \
      docker-ce-cli \
      docker-buildx-plugin \
      docker-compose-plugin \
      && \
    curl -fsSL -o /tmp/upx.tar.xz "https://github.com/upx/upx/releases/download/v${UPX_VERSION}/upx-${UPX_VERSION}-${TARGETARCH}_linux.tar.xz" && \
    tar xf /tmp/upx.tar.xz -C /tmp "upx-${UPX_VERSION}-${TARGETARCH}_linux/upx" && \
    "/tmp/upx-${UPX_VERSION}-${TARGETARCH}_linux/upx" -q \
      /usr/libexec/docker/cli-plugins/docker-buildx \
      /usr/libexec/docker/cli-plugins/docker-compose && \
    rm -rf "/tmp/upx.tar.xz" "/tmp/upx-${UPX_VERSION}-${TARGETARCH}_linux" && \
    find /usr -name __pycache__ -exec rm -rf {} +

# ========================================================================================================
FROM system-base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
WORKDIR /tmp

# Instead of utilizing ENV statements, we make use of /etc/environment file to make the requisite
# environment variables available to all users of this image (primarily 'root' and 'coder')
# - set starting PATH variable value (this strips some Ubuntu defaults such as games and snap directories)
# - Make typing unicode characters in the terminal work (w/ LC_ALL + LANG).
RUN echo 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' > /etc/environment && \
    echo 'PYTHONPYCACHEPREFIX=/var/cache/python' >> /etc/environment && \
    echo 'LC_ALL=en_US.UTF-8' >> /etc/environment && \
    echo 'LANG=en_US.UTF-8' >> /etc/environment

ARG CODER_GID="10001"
ARG CODER_UID="10001"
RUN groupadd --gid "${CODER_GID}" coder && \
    useradd --uid "${CODER_UID}" --gid "${CODER_GID}" --home-dir /home/coder --create-home --shell /bin/bash coder && \
    mkdir -p /var/cache/python && \
    # enable both root user and coder group to maintain/cleanup PYTHONPYCACHEPREFIX dir
    chown -R root:coder /var/cache/python && \
    chmod 775 /var/cache/python && \
    # enable installing homebrew if needed (w/ write access to homebrew dir allowed by both root and coder users)
    mkdir -p /home/linuxbrew/.linuxbrew && \
    chmod 775 /home/linuxbrew/.linuxbrew && \
    # package installation is complete, users of resulting image need not cache downloaded packages
    rm -f /etc/apt/apt.conf.d/keep-cache

USER coder
WORKDIR /home/coder
