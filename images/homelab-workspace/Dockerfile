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

# yq
# renovate: datasource=github-releases depName=mikefarah/yq
ARG YQ_VERSION="4.44.6"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    wget --progress=dot:giga -c "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${TARGETARCH}.tar.gz" -O - | tar -xzv -C /tmp && \
    install -o root -g root -m 0755 /tmp/yq_linux_${TARGETARCH} /usr/local/sbin/yq && \
    upx /usr/local/sbin/yq

# fetch (used for installing packages from github release assets)
# renovate: datasource=github-releases depName=gruntwork-io/fetch
ARG FETCH_VERSION="0.4.6"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    wget --progress=dot:giga -c "https://github.com/gruntwork-io/fetch/releases/download/v${FETCH_VERSION}/fetch_linux_${TARGETARCH}" -O /tmp/fetch_linux && \
    install -o root -g root -m 0755 /tmp/fetch_linux /usr/local/sbin/fetch && \
    upx /usr/local/sbin/fetch

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
      inetutils-syslogd \
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
      psmisc \
      pv \
      python-is-python3 \
      python3 \
      python3-pip \
      python3-venv \
      rsync \
      screen \
      software-properties-common \
      sshpass \
      ssh-askpass \
      strace \
      sysstat \
      traceroute \
      tmux \
      tzdata \
      vim \
      watch \
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
FROM base AS sdk-nodejs
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
WORKDIR /tmp

# renovate: datasource=github-releases depName=Schniz/fnm
ENV FNM_VERSION="1.38.1"
ENV FNM_ROOT=/opt/fnm
ENV PATH="$PATH:${FNM_ROOT}"
# hadolint ignore=SC2086
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    --mount=type=secret,id=FETCH_GH_TOKEN \
    export FNM_RELEASE_ASSET="$(test "${TARGETARCH}" == "arm64" && echo "fnm-arm64.zip" || echo "fnm-linux.zip")" && \
    fetch \
        --repo="https://github.com/Schniz/fnm" \
        --tag="v${FNM_VERSION}" \
        --release-asset="${FNM_RELEASE_ASSET}" \
        --github-oauth-token="$(cat /run/secrets/FETCH_GH_TOKEN)" \
        /tmp && \
    unzip $FNM_RELEASE_ASSET && \
    mkdir -p $FNM_ROOT && \
    install -o root -g root -m 0755 /tmp/fnm $FNM_ROOT/fnm && \
    upx $FNM_ROOT/fnm && \
    mkdir /env && \
    echo "FNM_ROOT=$FNM_ROOT" > /env/fnm.env && \
    echo "$FNM_ROOT" > /env/fnm.path

# ========================================================================================================
FROM base AS sdk-terraform
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
WORKDIR /tmp

# tfenv + terraform
# renovate: datasource=github-releases depName=tfutils/tfenv
ARG TFENV_VERSION="3.0.0"
ENV PATH="${PATH}:/opt/tfenv/bin"
# hadolint ignore=SC2016
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    git clone -b "v${TFENV_VERSION}" --depth=1 https://github.com/tfutils/tfenv.git /opt/tfenv 2> /dev/null && \
    chmod -R g+rw /opt/tfenv && \
    mkdir /env && \
    echo "/opt/tfenv/bin" > /env/terraform.path


# ========================================================================================================
FROM base AS binary-downloads
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
WORKDIR /tmp

# kubectl version=latest(intersect(stable-channel(https://github.com/k3s-io/k3s/releases), https://github.com/kubernetes/kubernetes/releases))
# renovate: datasource=github-releases depName=kubernetes/kubernetes
ARG KUBECTL_VERSION="1.31.4"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    wget --progress=dot:giga "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" -O /tmp/kubectl && \
    wget --progress=dot:giga "https://dl.k8s.io/v${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl.sha256" -O /tmp/kubectl.sha256 && \
    echo "$(cat /tmp/kubectl.sha256)  /tmp/kubectl" | sha256sum --check && \
    install -o root -g root -m 0755 /tmp/kubectl /usr/local/sbin/kubectl && \
    upx /usr/local/sbin/kubectl

# flux
# renovate: datasource=github-releases depName=fluxcd/flux2
ARG FLUX_VERSION="2.4.0"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    wget --progress=dot:giga -c "https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}/flux_${FLUX_VERSION}_linux_${TARGETARCH}.tar.gz" -O - | tar -xzv -C /tmp && \
    install -o root -g root -m 0755 /tmp/flux /usr/local/sbin/flux && \
    upx /usr/local/sbin/flux

# krew
# renovate: datasource=github-releases depName=kubernetes-sigs/krew
ARG KREW_VERSION="0.4.4"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    wget --progress=dot:giga -c "https://github.com/kubernetes-sigs/krew/releases/download/v${KREW_VERSION}/krew-linux_${TARGETARCH}.tar.gz" -O - | tar -xzv -C /tmp && \
    install -o root -g root -m 0755 /tmp/krew-linux_${TARGETARCH} /usr/local/sbin/kubectl-krew && \
    upx /usr/local/sbin/kubectl-krew

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
ARG AQUA_VERSION="2.40.0"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    wget --progress=dot:giga -c "https://github.com/aquaproj/aqua/releases/download/v${AQUA_VERSION}/aqua_linux_${TARGETARCH}.tar.gz" -O - | tar -xzv -C /tmp && \
    install -o root -g root -m 0755 /tmp/aqua /usr/local/sbin/aqua && \
    upx /usr/local/sbin/aqua

# gh
# renovate: datasource=github-releases depName=cli/cli
ARG GH_VERSION="2.63.2"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    wget --progress=dot:giga -c "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${TARGETARCH}.tar.gz" -O - | tar -xzv --strip-components 2 -C /tmp gh_${GH_VERSION}_linux_${TARGETARCH}/bin/gh && \
    install -o root -g root -m 0755 /tmp/gh /usr/local/sbin/gh && \
    upx /usr/local/sbin/gh

# minio-cli
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    curl -s -q "https://dl.min.io/client/mc/release/linux-${TARGETARCH}/mc" -o /tmp/mc && \
    install -o root -g root -m 0755 /tmp/mc /usr/local/sbin/mc && \
    upx /usr/local/sbin/mc


# ========================================================================================================
FROM system-base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
WORKDIR /tmp

# copy sdks + packages installations
COPY --from=sdk-nodejs /opt/fnm /opt/fnm
COPY --from=sdk-terraform /opt/tfenv /opt/tfenv

# copy binaries
COPY --from=binary-downloads /usr/local/sbin/* /usr/local/sbin/

# copy environment variables
# hadolint ignore=SC2086
RUN --mount=type=bind,from=sdk-nodejs,source=/env,target=/env/sdk-nodejs \
    --mount=type=bind,from=sdk-terraform,source=/env,target=/env/sdk-terraform \
    --mount=type=tmpfs,target=/tmp \
    # ----------------------------------------------------------------------------------------------------
    # join path segments from /env/*.path and add to PATH env var in /etc/environment
    for path_file in $(find /env -type f -name *.path | sort); do export PATH="$(cat $path_file):${PATH}"; done && \
    mv /etc/environment /tmp/env.tmp && \
    grep -v '^PATH=' /tmp/env.tmp > /etc/environment && \
    echo 'PATH="'${PATH}'"' >> /etc/environment && \
    # ----------------------------------------------------------------------------------------------------
    # add all environment values from /env/*.env files to /etc/environment
    for env_file in $(find /env -type f -name *.env | sort); do cat $env_file >> /etc/environment; done


ARG CODER_GID="10001"
ARG CODER_UID="10001"
RUN groupadd --gid ${CODER_GID} coder && \
    useradd --uid ${CODER_UID} --gid ${CODER_GID} --home-dir /home/coder --create-home --shell /bin/bash coder && \
    chown -R root:coder /var/cache/python && \
    chown -R root:coder /opt/tfenv
USER coder
WORKDIR /home/coder
