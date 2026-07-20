FROM ubuntu:noble@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90 AS base
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

# ========================================================================================================
# Rootless Docker support (the runtime kind/Kubernetes-in-Docker relies on; kind itself is installed by the
# user via aqua in their dotfiles, not baked into the image).
# Kept as a self-contained block (separate from the general toolset above) so it can later be lifted into a
# dedicated variant image without untangling it from the base package list.
# - uidmap:         provides newuidmap/newgidmap (setuid-root) needed to map subordinate uid/gid ranges
# - slirp4netns:    userspace network stack for rootless dockerd (no CAP_NET_ADMIN required)
# - fuse-overlayfs: fallback storage driver; native overlay2 (userns + kernel>=5.11) is the primary path,
#                   used when /dev/fuse is unavailable (the unprivileged pod has no /dev/fuse)
# - iptables:       required by dockerd/kind for bridge + port-mapping rules
# We use Docker's official apt repo (not Ubuntu's docker.io) so the rootless entrypoints ship in the
# docker-ce-rootless-extras package (dockerd-rootless.sh / dockerd-rootless-setuptool.sh).
RUN --mount=type=cache,target=/var/cache/apt,id=cache-apt-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/var/cache/debconf,id=cache-debconf-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/var/lib/apt,id=lib-apt-${TARGETARCH},sharing=locked \
    --mount=type=tmpfs,target=/var/cache/python \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    # rootless-docker runtime dependencies (from Ubuntu repos)
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -yq \
      fuse-overlayfs \
      iptables \
      slirp4netns \
      uidmap \
      && \
    # add Docker's official apt repository + signing key (arch matched to the build platform)
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=${TARGETARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
      > /etc/apt/sources.list.d/docker.list && \
    # Docker engine + CLI + buildx + containerd. docker-ce-rootless-extras is a
    # SEPARATE package (not pulled in by docker-ce) that ships dockerd-rootless.sh
    # and dockerd-rootless-setuptool.sh -- the rootless entrypoints this image needs.
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -yq \
      containerd.io \
      docker-buildx-plugin \
      docker-ce \
      docker-ce-cli \
      docker-ce-rootless-extras \
      && \
    # Clean pycache created during apt-get install (as apt stills retains some crud in spite of PYTHONPYCACHEPREFIX)
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

# Guarantee subordinate uid/gid ranges for 'coder' so rootless dockerd can map users inside its userns.
# useradd does not reliably populate /etc/subuid+/etc/subgid at build time, so ensure them idempotently
# (append only if no entry for coder exists; never clobber ranges already present at runtime).
# newuidmap/newgidmap must stay setuid-root for the mapping to work - verify, and do NOT strip the bits.
RUN touch /etc/subuid /etc/subgid && \
    grep -q '^coder:' /etc/subuid || echo 'coder:100000:65536' >> /etc/subuid && \
    grep -q '^coder:' /etc/subgid || echo 'coder:100000:65536' >> /etc/subgid && \
    test -u /usr/bin/newuidmap && test -u /usr/bin/newgidmap

USER coder
WORKDIR /home/coder
