FROM ubuntu:noble@sha256:80dd3c3b9c6cecb9f1667e9290b3bc61b78c2678c02cbdae5f0fea92cc6734ab AS base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH

# set starting PATH variable value (this strips some Ubuntu defaults such as games and snap directories)
ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
# overwrite /etc/environment with updated PATH value
# hadolint ignore=DL3059
RUN echo 'PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' > /etc/environment

# Place all __pycache__ and *.pyc within a location outside of /usr or /opt,
# - so that it can be easily cleared by the user (as needed)
# - so that they need not be built into the image
# This is done early on as the next RUN statement installs python3 along with several packages that depend on python
# and use them within the scope of that statement.
ENV PYTHONPYCACHEPREFIX=/var/cache/python
RUN mkdir -p /var/cache/python && \
    chmod 775 /var/cache/python && \
    echo 'PYTHONPYCACHEPREFIX=/var/cache/python' >> /etc/environment && \
    find /usr -name __pycache__ -exec rm -rf {} +

RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# minimum requirements for base image (for supporting builds of subsequent stages)
RUN --mount=type=cache,target=/var/cache/apt,id=cache-apt-${TARGETARCH},sharing=shared \
    --mount=type=cache,target=/var/cache/debconf,id=cache-debconf-${TARGETARCH},sharing=shared \
    --mount=type=cache,target=/var/lib/apt,id=lib-apt-${TARGETARCH},sharing=shared \
    --mount=type=tmpfs,target=/var/cache/python \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends \
        apt-transport-https \
        bash \
        ca-certificates \
        curl \
        git \
        gnupg \
        jq \
        locales \
        sudo \
        unzip \
        wget \
        xz-utils && \
    find /usr -name __pycache__ -exec rm -rf {} +

# generate locales (needed for many applications, specially python)
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    echo "LANG=en_US.UTF-8" > /etc/locale.conf && \
    locale-gen en_US.UTF-8
# Make typing unicode characters in the terminal work.
ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8
RUN echo 'LC_ALL=en_US.UTF-8' >> /etc/environment && \
    echo 'LANG=en_US.UTF-8' >> /etc/environment

# upx
# renovate: datasource=github-releases depName=upx/upx
ARG UPX_VERSION="4.2.4"
WORKDIR /tmp
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    wget  --progress=dot:giga "https://github.com/upx/upx/releases/download/v${UPX_VERSION}/upx-${UPX_VERSION}-${TARGETARCH}_linux.tar.xz" -O /tmp/upx.tar.xz && \
    xz -d /tmp/upx.tar.xz && \
    tar xvf upx.tar -C /usr/local/sbin --strip-components 1 "upx-${UPX_VERSION}-${TARGETARCH}_linux/upx"

# ========================================================================================================
FROM base AS system-base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH

# unminimize
RUN --mount=type=cache,target=/var/cache/apt,id=cache-apt-${TARGETARCH},sharing=shared \
    --mount=type=cache,target=/var/cache/debconf,id=cache-debconf-${TARGETARCH},sharing=shared \
    --mount=type=cache,target=/var/lib/apt,id=lib-apt-${TARGETARCH},sharing=shared \
    --mount=type=tmpfs,target=/var/cache/python \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends man-db unminimize && \
    sed -i 's|xargs dpkg -S|xargs -r dpkg -S|g' /usr/bin/unminimize && \
    echo -e 'y\ny' | /usr/bin/unminimize && \
    find /usr -name __pycache__ -exec rm -rf {} +

# system packages
RUN --mount=type=cache,target=/var/cache/apt,id=cache-apt-${TARGETARCH},sharing=shared \
    --mount=type=cache,target=/var/cache/debconf,id=cache-debconf-${TARGETARCH},sharing=shared \
    --mount=type=cache,target=/var/lib/apt,id=lib-apt-${TARGETARCH},sharing=shared \
    --mount=type=tmpfs,target=/var/cache/python \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -yq \
      autoconf \
      bash-completion \
      bsdextrautils \
      build-essential \
      dnsutils \
      ffmpeg \
      fontconfig \
      gettext \
      htop \
      inetutils-tools \
      iotop \
      iputils-ping \
      iputils-tracepath \
      ldap-utils \
      less \
      libarchive-dev \
      libarchive-tools \
      libheif-dev \
      libraw-dev \
      libssl-dev \
      libtool \
      lsof \
      lz4 \
      nano \
      netcat-openbsd \
      net-tools \
      nmap \
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
      sysstat \
      traceroute \
      tmux \
      tzdata \
      vim \
      zip \
      zstd \
      && \
    find /usr -name __pycache__ -exec rm -rf {} +

RUN --mount=type=cache,target=/var/cache/apt,id=cache-apt-${TARGETARCH},sharing=shared \
    --mount=type=cache,target=/var/cache/debconf,id=cache-debconf-${TARGETARCH},sharing=shared \
    --mount=type=cache,target=/var/lib/apt,id=lib-apt-${TARGETARCH},sharing=shared \
    --mount=type=tmpfs,target=/var/cache/python \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    rm -f /etc/apt/apt.conf.d/keep-cache


# ========================================================================================================
FROM base AS binary-downloads
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
WORKDIR /tmp

# starship
# renovate: datasource=github-releases depName=starship/starship
ARG STARSHIP_VERSION="1.21.1"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    STARSHIP_ARCH="$(echo $TARGETARCH | sed -e 's|amd64|x86_64|' | sed -e 's|arm64|aarch64|')" && \
    wget --progress=dot:giga -c "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-${STARSHIP_ARCH}-unknown-linux-musl.tar.gz" -O - | tar -xzv -C /tmp && \
    install -o root -g root -m 0755 /tmp/starship /usr/local/sbin/starship && \
    upx /usr/local/sbin/starship

# aqua
# renovate: datasource=github-releases depName=aquaproj/aqua
ARG AQUA_VERSION="2.42.2"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    wget --progress=dot:giga -c "https://github.com/aquaproj/aqua/releases/download/v${AQUA_VERSION}/aqua_linux_${TARGETARCH}.tar.gz" -O - | tar -xzv -C /tmp && \
    install -o root -g root -m 0755 /tmp/aqua /usr/local/sbin/aqua && \
    upx /usr/local/sbin/aqua

# mise-en-place
# renovate: datasource=github-releases depName=jdx/mise
ARG MISE_EN_PLACE_VERSION="2025.1.3"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    curl https://mise.run | MISE_VERSION="v${MISE_EN_PLACE_VERSION}" MISE_INSTALL_PATH=/tmp/mise sh && \
    install -o root -g root -m 0755 /tmp/mise /usr/local/sbin/mise && \
    upx /usr/local/sbin/mise


# ========================================================================================================
FROM system-base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
WORKDIR /tmp

# copy binaries
COPY --from=binary-downloads /usr/local/sbin/* /usr/local/sbin/

ARG CODER_GID="10001"
ARG CODER_UID="10001"
RUN groupadd --gid ${CODER_GID} coder && \
    useradd --uid ${CODER_UID} --gid ${CODER_GID} --home-dir /home/coder --create-home --shell /bin/bash coder && \
    chown -R root:coder /var/cache/python
USER coder
WORKDIR /home/coder
