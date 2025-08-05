FROM ubuntu:noble@sha256:a08e551cb33850e4740772b38217fc1796a66da2506d312abe51acda354ff061 AS base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH

# Place all __pycache__ and *.pyc within a location outside of /usr or /opt,
# - so that it can be easily cleared by the user (as needed)
# - so that they need not be built into the image
# This is done early on as the next RUN statement installs python3 along with several packages that depend on python
# and use them within the scope of that statement.
ENV PYTHONPYCACHEPREFIX=/var/cache/python

RUN --mount=type=cache,target=/var/cache/apt,id=cache-apt-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/var/cache/debconf,id=cache-debconf-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/var/lib/apt,id=lib-apt-${TARGETARCH},sharing=locked \
    --mount=type=tmpfs,target=/var/cache/python \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    chmod 775 /var/cache/python && \
    # enable caching of apt packages
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
    # minimum requirements for base image (for supporting builds of subsequent stages)
    apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends \
        apt-transport-https \
        bash \
        ca-certificates \
        curl \
        git \
        jq \
        locales \
        sudo \
        unzip \
        wget \
        xz-utils && \
    # generate locales (needed for many applications, specially python)
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    echo "LANG=en_US.UTF-8" > /etc/locale.conf && \
    LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 locale-gen en_US.UTF-8 && \
    # update environment variables (that we need to persist across build stages) in /etc/environment
    # - set starting PATH variable value (this strips some Ubuntu defaults such as games and snap directories)
    echo 'PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' > /etc/environment && \
    echo 'PYTHONPYCACHEPREFIX=/var/cache/python' >> /etc/environment && \
    # - Make typing unicode characters in the terminal work.
    echo 'LC_ALL=en_US.UTF-8' >> /etc/environment && \
    echo 'LANG=en_US.UTF-8' >> /etc/environment && \
    # Clean pycache created during install
    find /usr -name __pycache__ -exec rm -rf {} +

# upx
# renovate: datasource=github-releases depName=upx/upx
ARG UPX_VERSION="5.0.2"
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

ENV PYTHONPYCACHEPREFIX=/var/cache/python
RUN --mount=type=cache,target=/var/cache/apt,id=cache-apt-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/var/cache/debconf,id=cache-debconf-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/var/lib/apt,id=lib-apt-${TARGETARCH},sharing=locked \
    --mount=type=tmpfs,target=/var/cache/python \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    # unminimize
    apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends man-db unminimize && \
    sed -i 's|xargs dpkg -S|xargs -r dpkg -S|g' /usr/bin/unminimize && \
    echo -e 'y\ny' | /usr/bin/unminimize && \
    # system packages
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -yq \
      apt-file \
      apt-utils \
      bash-completion \
      bc \
      binutils \
      bsdextrautils \
      coreutils \
      dnsutils \
      fontconfig \
      gettext \
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
      sysstat \
      tmux \
      traceroute \
      tree \
      tzdata \
      vim \
      zip \
      zstd \
      && \
    rm -f /etc/apt/apt.conf.d/keep-cache && \
    find /usr -name __pycache__ -exec rm -rf {} +

# ========================================================================================================
FROM base AS binary-downloads
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
WORKDIR /tmp

ENV PATH=/root/.local/share/aquaproj-aqua/bin:$PATH
ENV AQUA_GLOBAL_CONFIG=/etc/aqua/aqua.yaml
COPY aqua.yaml aqua-checksums.json /etc/aqua/

# renovate: datasource=github-releases depName=aquaproj/aqua-installer
ARG AQUA_INSTALLER_VERSION="4.0.2"
# renovate: datasource=github-releases depName=aquaproj/aqua
ARG AQUA_VERSION="2.53.7"

# hadolint ignore=SC2046
RUN curl -sSfL -O https://raw.githubusercontent.com/aquaproj/aqua-installer/v${AQUA_INSTALLER_VERSION}/aqua-installer && \
    chmod +x aqua-installer && \
    ./aqua-installer -v v${AQUA_VERSION} && \
    aqua install --all && \
    mkdir -p /dist && \
    aqua cp -o /dist $(find /root/.local/share/aquaproj-aqua/bin -type l -executable -not -name upx -exec basename {} \;) && \
    upx $(find /dist  -type f -executable)

# ========================================================================================================
FROM system-base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
WORKDIR /tmp

# copy binaries
COPY --from=binary-downloads --chown=root:root --chmod=755 /dist/* /usr/local/sbin/

ARG CODER_GID="10001"
ARG CODER_UID="10001"
RUN groupadd --gid ${CODER_GID} coder && \
    useradd --uid ${CODER_UID} --gid ${CODER_GID} --home-dir /home/coder --create-home --shell /bin/bash coder && \
    mkdir -p /var/cache/python && \
    chown -R root:coder /var/cache/python
USER coder
WORKDIR /home/coder
