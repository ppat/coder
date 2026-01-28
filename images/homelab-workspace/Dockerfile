FROM ubuntu:noble@sha256:cd1dba651b3080c3686ecf4e3c4220f026b521fb76978881737d24f200828b2b AS base
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
FROM base AS binary-downloads
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
WORKDIR /tmp

ENV AQUA_ROOT_DIR=$HOME/.local/share/aquaproj-aqua
ENV PATH=$AQUA_ROOT_DIR/bin:$PATH
ENV AQUA_GLOBAL_CONFIG=/etc/aqua/aqua.yaml
COPY aqua.yaml aqua-checksums.json /etc/aqua/

# renovate: datasource=github-releases depName=aquaproj/aqua
ARG AQUA_VERSION="2.56.5"
# hadolint ignore=SC2046
RUN --mount=type=cache,target=$AQUA_ROOT_DIR,id=cache-aqua-${TARGETARCH},sharing=locked \
    --mount=type=tmpfs,target=/tmp \
    mkdir -p $AQUA_ROOT_DIR/bin && \
    mkdir -p /dist && \
    # Download and install aqua
    curl -fsSL -O "https://github.com/aquaproj/aqua/releases/download/v${AQUA_VERSION}/aqua_linux_${TARGETARCH}.tar.gz" && \
    curl -fsSL -o checksums.txt "https://github.com/aquaproj/aqua/releases/download/v${AQUA_VERSION}/aqua_${AQUA_VERSION}_checksums.txt" && \
    grep -E "aqua_linux_${TARGETARCH}.tar.gz$" checksums.txt > aqua_artifact_checksum.txt && \
    sha256sum -c aqua_artifact_checksum.txt && \
    tar xzf "aqua_linux_${TARGETARCH}.tar.gz" aqua && \
    mv ./aqua $AQUA_ROOT_DIR/bin/aqua && \
    chmod +x $AQUA_ROOT_DIR/bin/aqua && \
    echo "aqua v$AQUA_VERSION installed successfully" && \
    # Install packages w/ aqua as defined in aqua.yaml
    aqua install --all && \
    aqua cp -o /dist $(find $AQUA_ROOT_DIR/bin -type l -not -name upx -exec basename {} \; | sort) && \
    cp $AQUA_ROOT_DIR/bin/aqua /dist/aqua && \
    upx $(find /dist -type f -executable)

# ========================================================================================================
FROM system-base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
WORKDIR /tmp

# copy binaries from aqua based binary install stage
COPY --from=binary-downloads --chown=root:root --chmod=755 /dist/* /usr/local/sbin/

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
