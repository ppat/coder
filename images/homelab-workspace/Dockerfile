FROM ubuntu:resolute@sha256:2260313b31c8c011cd2eebe728008efac1b3982be73eb71348ea2648d2c0e09b AS base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH

RUN --mount=type=cache,target=/var/cache/apt,id=cache-apt-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/var/cache/debconf,id=cache-debconf-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/var/lib/apt,id=lib-apt-${TARGETARCH},sharing=locked \
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
    LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 locale-gen en_US.UTF-8

# ========================================================================================================
FROM base AS system-base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH

RUN --mount=type=cache,target=/var/cache/apt,id=cache-apt-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/var/cache/debconf,id=cache-debconf-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/var/lib/apt,id=lib-apt-${TARGETARCH},sharing=locked \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    apt-get update && \
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
      g++ \
      gcc \
      gettext \
      git \
      htop \
      inetutils-tools \
      iputils-ping \
      iputils-tracepath \
      less \
      libarchive-tools \
      libc6-dev \
      lsof \
      lz4 \
      make \
      nano \
      netcat-openbsd \
      net-tools \
      openssh-client \
      pkg-config \
      procps \
      psmisc \
      pv \
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
      zstd

# Docker CLI only (no docker-ce/containerd.io) - this workspace pod is unprivileged by design and has no
# local dockerd; the CLI talks to a remote daemon over `DOCKER_HOST=ssh://...`. A local docker group/sudo
# rule would authorize access to a local socket that doesn't exist here - don't add one. buildx/compose
# are client-side plugins, so a remote daemon doesn't provide them; the apt packages install to
# /usr/libexec/docker/cli-plugins, one of the docker CLI's default plugin search paths, so `docker buildx`/
# `docker compose` resolve without extra configuration.
# renovate: datasource=github-releases depName=upx/upx
ARG UPX_VERSION="5.2.1"
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
    rm -rf "/tmp/upx.tar.xz" "/tmp/upx-${UPX_VERSION}-${TARGETARCH}_linux"

# ========================================================================================================
FROM system-base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
WORKDIR /tmp

# Instead of utilizing ENV statements, we make use of /etc/environment file to make the requisite
# environment variables available to all users of this image (primarily 'root' and 'coder')
# - set starting PATH variable value (this strips some Ubuntu defaults such as games and snap directories)
RUN echo 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' > /etc/environment && \
    # Place all __pycache__ and *.pyc within a location outside of /usr or /opt,
    # - so that it can be easily cleared by the user (as needed)
    # - so that they need not be built into the image
    echo 'PYTHONPYCACHEPREFIX=/var/cache/python' >> /etc/environment && \
    # - Make typing unicode characters in the terminal work (w/ LC_ALL + LANG).
    echo 'LC_ALL=en_US.UTF-8' >> /etc/environment && \
    echo 'LANG=en_US.UTF-8' >> /etc/environment && \
    # This image has no dbus session bus and never will (no session manager, no systemd --user). Without
    # this, anything that touches libsecret (e.g. git credential helpers) triggers `dbus-launch
    # --autolaunch` to spawn a `dbus-daemon --session` hunting for one; it never finds one, is reparented
    # to pid 1 once its parent exits, and never exits itself - orphans accumulate one per invocation for
    # the life of the pod. `disabled:` is dbus's own documented value for "do not autolaunch, fail fast
    # instead" (see dbus_bus_get behavior), which is what every libsecret-using tool here already handles
    # as "no keyring available" rather than as an error.
    echo 'DBUS_SESSION_BUS_ADDRESS=disabled:' >> /etc/environment

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

USER ${CODER_UID}:${CODER_GID}
WORKDIR /home/coder
