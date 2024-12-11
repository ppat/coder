FROM --platform=$TARGETPLATFORM ubuntu:noble@sha256:278628f08d4979fb9af9ead44277dbc9c92c2465922310916ad0c46ec9999295 AS base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH

# set starting PATH variable value (this strips some Ubuntu defaults such as games and snap directories)
ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
# overwrite /etc/environment with updated PATH value
# hadolint ignore=DL3059
RUN echo 'PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' > /etc/environment

# Add `coder` group
# hadolint ignore=DL3059
RUN groupadd coder

# Place all __pycache__ and *.pyc within a location outside of /usr or /opt,
# - so that it can be easily cleared by the user (as needed)
# - so that they need not be built into the image
# This is done early on as the next RUN statement installs python3 along with several packages that depend on python
# and use them within the scope of that statement.
ENV PYTHONPYCACHEPREFIX=/var/cache/python
RUN mkdir -p /var/cache/python && \
    chown -R root:coder /var/cache/python && \
    chmod 775 /var/cache/python && \
    echo 'PYTHONPYCACHEPREFIX=/var/cache/python' >> /etc/environment && \
    find /usr -name __pycache__ -exec rm -rf {} +

RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# minimum requirements for base image (for supporting builds of subsequent stages)
RUN --mount=type=cache,target=/var/cache/apt,id=base-cache-apt-${TARGETARCH} \
    --mount=type=cache,target=/var/cache/debconf,id=base-cache-debconf-${TARGETARCH} \
    --mount=type=cache,target=/var/lib/apt,id=base-lib-apt-${TARGETARCH} \
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
        xz-utils

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
RUN wget  --progress=dot:giga "https://github.com/upx/upx/releases/download/v${UPX_VERSION}/upx-${UPX_VERSION}-${TARGETARCH}_linux.tar.xz" -O /tmp/upx.tar.xz && \
    xz -d /tmp/upx.tar.xz && \
    tar xvf upx.tar -C /usr/local/sbin --strip-components 1 "upx-${UPX_VERSION}-${TARGETARCH}_linux/upx" && \
    rm -rf /var/log/* /tmp/* /var/tmp/*

# yq
# renovate: datasource=github-releases depName=mikefarah/yq
ARG YQ_VERSION="4.44.6"
RUN wget --progress=dot:giga -c "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${TARGETARCH}.tar.gz" -O - | tar -xzv -C /tmp && \
    install -o root -g root -m 0755 /tmp/yq_linux_${TARGETARCH} /usr/local/sbin/yq && \
    upx /usr/local/sbin/yq && \
    rm -rf /tmp/* /var/log/* /var/tmp/*

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
FROM --platform=$TARGETPLATFORM base AS system-base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH

# # unminimize
# RUN --mount=type=cache,target=/var/cache/apt,id=sysbase1-cache-apt-${TARGETARCH} \
#     --mount=type=cache,target=/var/cache/debconf,id=sysbase1-cache-debconf-${TARGETARCH} \
#     --mount=type=cache,target=/var/lib/apt,id=sysbase1-lib-apt-${TARGETARCH} \
#     --mount=type=tmpfs,target=/var/cache/python \
#     --mount=type=tmpfs,target=/tmp \
#     --mount=type=tmpfs,target=/var/log \
#     --mount=type=tmpfs,target=/var/tmp \
#     apt-get update && \
#     DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends man-db && \
#     sed -i 's|xargs dpkg -S|xargs -r dpkg -S|g' /usr/local/sbin/unminimize && \
#     echo -e 'y\ny' | unminimize

# install docker-engine
# hadolint ignore=SC1091
RUN --mount=type=cache,target=/var/cache/apt,id=sysbase3-cache-apt-${TARGETARCH} \
    --mount=type=cache,target=/var/cache/debconf,id=sysbase3-cache-debconf-${TARGETARCH} \
    --mount=type=cache,target=/var/lib/apt,id=sysbase3-lib-apt-${TARGETARCH} \
    --mount=type=tmpfs,target=/var/cache/python \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    # prep apt source for docker
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo \
      "deb [arch="${TARGETARCH}" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    # install docker
    apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install --yes --no-install-recommends \
      containerd.io  \
      docker-ce \
      docker-ce-cli \
      docker-ce-rootless-extras \
      docker-buildx-plugin \
      docker-compose-plugin \
    && \
    # compress really large files (this will shave about 216MB off the size of final image)
    upx \
      /usr/bin/containerd \
      /usr/bin/containerd-shim \
      /usr/bin/containerd-shim-runc-v1 \
      /usr/bin/containerd-shim-runc-v2 \
      /usr/bin/ctr \
      /usr/bin/docker \
      /usr/bin/dockerd \
      /usr/bin/rootlesskit \
      /usr/bin/runc \
      /usr/libexec/docker/cli-plugins/docker-buildx  \
      /usr/libexec/docker/cli-plugins/docker-compose

# system packages
RUN --mount=type=cache,target=/var/cache/apt,id=sysbase4-cache-apt-${TARGETARCH} \
    --mount=type=cache,target=/var/cache/debconf,id=sysbase4-cache-debconf-${TARGETARCH} \
    --mount=type=cache,target=/var/lib/apt,id=sysbase4-lib-apt-${TARGETARCH} \
    --mount=type=tmpfs,target=/var/cache/python \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -yq \
      autoconf \
      bash-completion \
      bat \
      bsdextrautils \
      build-essential \
      cron \
      direnv \
      dnsutils \
      eza \
      fd-find \
      ffmpeg \
      fish \
      fontconfig \
      fzf \
      gettext \
      htop \
      hyperfine \
      inetutils-tools \
      inetutils-syslogd \
      iotop \
      iputils-ping \
      iputils-tracepath \
      jsonnet \
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
      ripgrep \
      rsync \
      screen \
      software-properties-common \
      sshpass \
      ssh-askpass \
      strace \
      supervisor \
      sysstat \
      traceroute \
      tmux \
      tzdata \
      vim \
      watch \
      zip \
      zsh \
      zstd


# ========================================================================================================
FROM --platform=$TARGETPLATFORM base AS sdk-nodejs
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
FROM --platform=$TARGETPLATFORM base AS sdk-golang
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
WORKDIR /tmp

# Golang (as per official instructions from https://go.dev/doc/install)
# renovate: datasource=golang-version depName=golang
ARG GOLANG_VERSION="1.23.4"
ENV GOROOT="/usr/local/go"
ENV PATH="$PATH:$GOROOT/bin"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    wget --progress=dot:giga "https://go.dev/dl/go${GOLANG_VERSION}.linux-${TARGETARCH}.tar.gz" -O /tmp/golang.tar.gz && \
    tar -C /usr/local -xzf /tmp/golang.tar.gz && \
    mkdir /env && \
    echo "GOROOT=$GOROOT" > /env/golang.env && \
    echo "$GOROOT/bin" > /env/golang.path

# kind
# renovate: datasource=github-releases depName=kubernetes-sigs/kind
ARG KIND_VERSION="0.25.0"
RUN --mount=type=tmpfs,target=/tmp \
    export GOPATH="/usr/local" && \
    go install "sigs.k8s.io/kind@v${KIND_VERSION}" && \
    upx /usr/local/bin/kind && \
    unset GOPATH


# ========================================================================================================
FROM --platform=$TARGETPLATFORM base AS sdk-rust-cargo
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
WORKDIR /tmp

# Rust / Cargo
ENV CARGO_HOME="/opt/cargo"
ENV PATH="$PATH:$CARGO_HOME/bin"
RUN --mount=type=cache,target=/root/.rustup,id=rustup-cache-${TARGETARCH} \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs/ | sh -s -- --default-toolchain=none --no-modify-path -y && \
    mkdir /env && \
    echo "CARGO_HOME=$CARGO_HOME" > /env/rust-cargo.env && \
    echo "$CARGO_HOME/bin" > /env/rust-cargo.path


# ========================================================================================================
FROM --platform=$TARGETPLATFORM base AS sdk-terraform
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
    chown -R root:coder /opt/tfenv && \
    chmod -R g+rw /opt/tfenv && \
    mkdir /env && \
    echo "/opt/tfenv/bin" > /env/terraform.path && \
    echo 'TFENV_CONFIG_DIR=$HOME/.tfenv' > /env/tfenv_dir.env


# ========================================================================================================
FROM --platform=$TARGETPLATFORM base AS binary-downloads
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
WORKDIR /tmp

# kubectl version=latest(intersect(stable-channel(https://github.com/k3s-io/k3s/releases), https://github.com/kubernetes/kubernetes/releases))
# renovate: datasource=github-releases depName=kubernetes/kubernetes
ARG KUBECTL_VERSION="1.31.3"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    wget --progress=dot:giga "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" -O /tmp/kubectl && \
    wget --progress=dot:giga "https://dl.k8s.io/v${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl.sha256" -O /tmp/kubectl.sha256 && \
    echo "$(cat /tmp/kubectl.sha256)  /tmp/kubectl" | sha256sum --check && \
    install -o root -g root -m 0755 /tmp/kubectl /usr/local/sbin/kubectl && \
    upx /usr/local/sbin/kubectl

# helm
# renovate: datasource=github-releases depName=helm/helm
ARG HELM_VERSION="3.16.3"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    wget --progress=dot:giga -c "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" -O - | tar -xzv --strip-components 1 -C /tmp && \
    install -o root -g root -m 0755 /tmp/helm /usr/local/sbin/helm && \
    upx /usr/local/sbin/helm

# packer
# renovate: datasource=github-releases depName=hashicorp/packer
ARG PACKER_VERSION="1.11.2"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    wget --progress=dot:giga -c "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_${TARGETARCH}.zip" -O /tmp/packer.zip && \
    unzip /tmp/packer.zip && \
    install -o root -g root -m 0755 /tmp/packer /usr/local/sbin/packer && \
    upx /usr/local/sbin/packer

# flux
# renovate: datasource=github-releases depName=fluxcd/flux2
ARG FLUX_VERSION="2.4.0"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    wget --progress=dot:giga -c "https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}/flux_${FLUX_VERSION}_linux_${TARGETARCH}.tar.gz" -O - | tar -xzv -C /tmp && \
    install -o root -g root -m 0755 /tmp/flux /usr/local/sbin/flux && \
    upx /usr/local/sbin/flux

# k9s
# renovate: datasource=github-releases depName=derailed/k9s
ARG K9S_VERSION="0.32.7"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    wget --progress=dot:giga -c "https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_Linux_${TARGETARCH}.tar.gz" -O - | tar -xzv -C /tmp && \
    install -o root -g root -m 0755 /tmp/k9s /usr/local/sbin/k9s && \
    upx /usr/local/sbin/k9s

# krew
# renovate: datasource=github-releases depName=kubernetes-sigs/krew
ARG KREW_VERSION="0.4.4"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    wget --progress=dot:giga -c "https://github.com/kubernetes-sigs/krew/releases/download/v${KREW_VERSION}/krew-linux_${TARGETARCH}.tar.gz" -O - | tar -xzv -C /tmp && \
    install -o root -g root -m 0755 /tmp/krew-linux_${TARGETARCH} /usr/local/sbin/kubectl-krew && \
    upx /usr/local/sbin/kubectl-krew

# kustomize
# renovate: datasource=github-releases depName=kubernetes-sigs/kustomize extractVersion=^kustomize/(?<version>.*)$
ARG KUSTOMIZE_VERSION="5.5.0"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    wget --progress=dot:giga -c "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_${TARGETARCH}.tar.gz" -O - | tar -xzv -C /tmp && \
    install -o root -g root -m 0755 /tmp/kustomize /usr/local/sbin/kustomize && \
    upx /usr/local/sbin/kustomize

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
FROM --platform=$TARGETPLATFORM system-base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
WORKDIR /tmp

# copy sdks + packages installations
COPY --from=sdk-nodejs /opt/fnm /opt/fnm
COPY --from=sdk-golang /usr/local/go /usr/local/go
COPY --from=sdk-terraform /opt/tfenv /opt/tfenv
COPY --from=sdk-rust-cargo /opt/cargo /opt/cargo

# copy binaries
COPY --from=binary-downloads /usr/local/sbin/* /usr/local/sbin/
COPY --from=sdk-rust-cargo /usr/local/bin/* /usr/local/sbin/
COPY --from=sdk-golang /usr/local/bin/* /usr/local/sbin/

# copy environment variables
# hadolint ignore=SC2086
RUN --mount=type=bind,from=sdk-nodejs,source=/env,target=/env/sdk-nodejs \
    --mount=type=bind,from=sdk-golang,source=/env,target=/env/sdk-golang \
    --mount=type=bind,from=sdk-terraform,source=/env,target=/env/sdk-terraform \
    --mount=type=bind,from=sdk-rust-cargo,source=/env,target=/env/sdk-rust-cargo \
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

# copy /etc config files
COPY --link --chown=root:root --chmod=644 etc/* /etc/

# coder initialization scripts
COPY --link --chown=root:root --chmod=755 coder/*.sh /opt/coder/bin/

RUN rm -f /etc/apt/apt.conf.d/keep-cache

WORKDIR /
