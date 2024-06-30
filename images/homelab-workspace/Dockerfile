FROM --platform=$TARGETPLATFORM ubuntu:jammy@sha256:19478ce7fc2ffbce89df29fea5725a8d12e57de52eb9ea570890dc5852aac1ac AS base
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
        build-essential \
        ca-certificates \
        curl \
        git \
        gnupg \
        jq \
        locales \
        man \
        python3 \
        python3-pip \
        software-properties-common \
        sudo \
        unzip \
        wget \
        xz-utils \
        zip

# generate locales (needed for many applications, specially python)
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    echo "LANG=en_US.UTF-8" > /etc/locale.conf && \
    locale-gen en_US.UTF-8
# Make typing unicode characters in the terminal work.
ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8
RUN echo 'LC_ALL=en_US.UTF-8' >> /etc/environment && \
    echo 'LANG=en_US.UTF-8' >> /etc/environment

# fetch and use upx to compress larger executables as this is already a large image
# this will be utilized in subsequent stages
# renovate: datasource=github-releases depName=upx/upx
ARG UPX_VERSION="4.2.4"
WORKDIR /tmp
RUN wget  --progress=dot:giga "https://github.com/upx/upx/releases/download/v${UPX_VERSION}/upx-${UPX_VERSION}-${TARGETARCH}_linux.tar.xz" -O /tmp/upx.tar.xz && \
    xz -d /tmp/upx.tar.xz && \
    tar xvf upx.tar -C /usr/local/sbin --strip-components 1 "upx-${UPX_VERSION}-${TARGETARCH}_linux/upx" && \
    rm -rf /var/log/* /tmp/* /var/tmp/*

# yq
# renovate: datasource=github-releases depName=mikefarah/yq
ARG YQ_VERSION="4.44.2"
RUN wget --progress=dot:giga -c "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${TARGETARCH}.tar.gz" -O - | tar -xzv -C /tmp && \
    install -o root -g root -m 0755 /tmp/yq_linux_${TARGETARCH} /usr/local/sbin/yq && \
    upx /usr/local/sbin/yq && \
    rm -rf /tmp/* /var/log/* /var/tmp/*


# ========================================================================================================
FROM --platform=$TARGETPLATFORM base AS system-base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH

# unminimize
RUN --mount=type=cache,target=/var/cache/apt,id=sysbase1-cache-apt-${TARGETARCH} \
    --mount=type=cache,target=/var/cache/debconf,id=sysbase1-cache-debconf-${TARGETARCH} \
    --mount=type=cache,target=/var/lib/apt,id=sysbase1-lib-apt-${TARGETARCH} \
    --mount=type=tmpfs,target=/var/cache/python \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    sed -i 's|xargs dpkg -S|xargs -r dpkg -S|g' /usr/local/sbin/unminimize && \
    echo -e 'y\ny' | unminimize

# systemd requirements (from https://github.com/nestybox/dockerfiles/blob/master/ubuntu-jammy-systemd/Dockerfile)
RUN --mount=type=cache,target=/var/cache/apt,id=sysbase2-cache-apt-${TARGETARCH} \
    --mount=type=cache,target=/var/cache/debconf,id=sysbase2-cache-debconf-${TARGETARCH} \
    --mount=type=cache,target=/var/lib/apt,id=sysbase2-lib-apt-${TARGETARCH} \
    --mount=type=tmpfs,target=/var/cache/python \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends \
      dbus \
      iptables \
      iproute2 \
      kmod \
      libsystemd0 \
      systemd \
      systemd-sysv \
      udev \
      && \
    # Prevents journald from reading kernel messages from /dev/kmsg
    echo "ReadKMsg=no" >> /etc/systemd/journald.conf && \
    # Disable systemd services/units that are unnecessary within a container.
    systemctl mask systemd-udevd.service \
      systemd-udevd-kernel.socket \
      systemd-udevd-control.socket \
      systemd-modules-load.service \
      sys-kernel-debug.mount \
      sys-kernel-tracing.mount

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
      cron \
      dnsutils \
      exa \
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
      ripgrep \
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
      watch \
      zsh \
      zstd

# enables docker starting with systemd
RUN systemctl enable docker


# ========================================================================================================
FROM --platform=$TARGETPLATFORM base AS sdk-nodejs
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
WORKDIR /tmp

# NodeJS/NPM/NPX: install latest LTS version
# renovate: datasource=node depName=node versioning=node
ARG NODE_VERSION="20.15.0"
ENV FNM_ROOT=/opt/fnm
ENV PATH="$PATH:${FNM_ROOT}"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    mkdir -p /opt/fnm && \
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell --install-dir ${FNM_ROOT} && \
    eval "$(${FNM_ROOT}/fnm env --shell bash --use-on-cd --fnm-dir ${FNM_ROOT})" && \
    ${FNM_ROOT}/fnm install ${NODE_VERSION} && \
    ${FNM_ROOT}/fnm use ${NODE_VERSION} && \
    ${FNM_ROOT}/fnm default --fnm-dir ${FNM_ROOT} ${NODE_VERSION} && \
    chown -R root:coder ${FNM_ROOT} && \
    chmod -R g+rw ${FNM_ROOT} && \
    chmod 755 ${FNM_ROOT}/fnm && \
    mkdir /env && \
    echo "FNM_ROOT=$FNM_ROOT" > /env/fnm.env && \
    echo "$FNM_ROOT" > /env/fnm.path

# NodeJS based tooling
# hadolint ignore=DL3016,SC2086
RUN --mount=type=bind,source=./packages,target=/packages \
    --mount=type=cache,target=/root/.npm,id=npm-cache-${TARGETARCH} \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    eval "$(${FNM_ROOT}/fnm env --shell bash --use-on-cd --fnm-dir ${FNM_ROOT})" && \
    ${FNM_ROOT}/fnm use ${NODE_VERSION} && \
    npm config set update-notifier false && \
    npm config set fund false && \
    npm config set loglevel error && \
    for i in $(cat /packages/npm-packages.json | jq -r '.devDependencies | to_entries | map([.key, .value] | join("@")) | .[]'); do echo $i; npm install -g $i; done && \
    chown -R root:coder ${FNM_ROOT} && \
    chmod -R g+rw ${FNM_ROOT}


# ========================================================================================================
FROM --platform=$TARGETPLATFORM base AS sdk-golang
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
WORKDIR /tmp

# Golang (as per official instructions from https://go.dev/doc/install)
# renovate: datasource=golang-version depName=golang
ARG GOLANG_VERSION="1.22.4"
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
ARG KIND_VERSION="0.23.0"
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
# renovate: datasource=github-releases depName=rust-lang/rust
ARG RUST_VERSION="1.77.0"
ENV CARGO_HOME="/opt/cargo"
ENV PATH="$PATH:$CARGO_HOME/bin"
RUN --mount=type=cache,target=/root/.rustup,id=rustup-cache-${TARGETARCH} \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs/ | sh -s -- --default-toolchain=none --no-modify-path -y && \
    mkdir /env && \
    echo "CARGO_HOME=$CARGO_HOME" > /env/rust-cargo.env && \
    echo "RUST_VERSION=$RUST_VERSION" >> /env/rust-cargo.env && \
    echo "$CARGO_HOME/bin" > /env/rust-cargo.path

# ========================================================================================================
FROM --platform=$TARGETPLATFORM base AS sdk-terraform
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
WORKDIR /tmp

# tfenv + terraform
# renovate: datasource=github-releases depName=tfutils/tfenv
ARG TFENV_VERSION="3.0.0"
# renovate: datasource=github-releases depName=hashicorp/terraform
ARG TERRAFORM_VERSION="1.8.5"
ENV PATH="${PATH}:/opt/tfenv/bin"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    git clone -b "v${TFENV_VERSION}" --depth=1 https://github.com/tfutils/tfenv.git /opt/tfenv 2> /dev/null && \
    tfenv install ${TERRAFORM_VERSION} && \
    tfenv use ${TERRAFORM_VERSION} && \
    upx /opt/tfenv/versions/${TERRAFORM_VERSION}/terraform && \
    chown -R root:coder /opt/tfenv && \
    chmod -R g+rw /opt/tfenv && \
    mkdir /env && \
    echo "/opt/tfenv/bin" > /env/terraform.path


# ========================================================================================================
FROM --platform=$TARGETPLATFORM base AS binary-downloads
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
WORKDIR /tmp

# kubectl version=latest(intersect(stable-channel(https://github.com/k3s-io/k3s/releases), https://github.com/kubernetes/kubernetes/releases))
# renovate: datasource=github-releases depName=kubernetes/kubernetes
ARG KUBECTL_VERSION="1.30.2"
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
ARG HELM_VERSION="3.15.2"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    wget --progress=dot:giga -c "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" -O - | tar -xzv --strip-components 1 -C /tmp && \
    install -o root -g root -m 0755 /tmp/helm /usr/local/sbin/helm && \
    upx /usr/local/sbin/helm

# packer
# renovate: datasource=github-releases depName=hashicorp/packer
ARG PACKER_VERSION="1.10.3"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    wget --progress=dot:giga -c "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_${TARGETARCH}.zip" -O /tmp/packer.zip && \
    unzip /tmp/packer.zip && \
    install -o root -g root -m 0755 /tmp/packer /usr/local/sbin/packer && \
    upx /usr/local/sbin/packer

# minio-cli
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    curl -s -q "https://dl.min.io/client/mc/release/linux-${TARGETARCH}/mc" -o /tmp/mc && \
    install -o root -g root -m 0755 /tmp/mc /usr/local/sbin/mc && \
    upx /usr/local/sbin/mc


# ========================================================================================================
FROM --platform=$TARGETPLATFORM base AS github-release-downloads
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
WORKDIR /tmp

# fetch (used for installing packages from github release assets)
# renovate: datasource=github-releases depName=gruntwork-io/fetch
ARG FETCH_VERSION="0.4.6"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    wget --progress=dot:giga -c "https://github.com/gruntwork-io/fetch/releases/download/v${FETCH_VERSION}/fetch_linux_${TARGETARCH}" -O /tmp/fetch_linux && \
    install -o root -g root -m 0755 /tmp/fetch_linux /usr/local/sbin/fetch && \
    upx /usr/local/sbin/fetch

# install apps from github releases
# hadolint ignore=SC2155
RUN --mount=type=bind,source=./packages,target=/packages \
    --mount=type=secret,id=FETCH_GH_TOKEN \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    export FETCH_GH_TOKEN="$(cat /run/secrets/FETCH_GH_TOKEN)" && \
    /bin/bash /packages/install-from-github-release.sh /packages/github-releases.yaml


# ========================================================================================================
FROM --platform=$TARGETPLATFORM system-base AS python-packages
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
WORKDIR /tmp

# python build and lint tools: (poetry, etc)
ENV PIPX_HOME=/opt/pipx
ENV PIPX_BIN_DIR=/opt/pipx/bin
ENV PATH="$PATH:$PIPX_BIN_DIR"
# hadolint ignore=DL3013,SC2086
RUN --mount=type=bind,source=./packages,target=/packages \
    --mount=type=cache,target=/root/.cache/pip,id=pipx-cache-${TARGETARCH} \
    --mount=type=tmpfs,target=/var/cache/python \
    --mount=type=tmpfs,target=/tmp \
    mkdir ${PIPX_HOME} && \
    for t in $(grep -v '^#' /packages/pipx-package-requirements.txt); do pipx install ${t}; done && \
    chown -R root:coder ${PIPX_HOME} && \
    chmod -R g+rw ${PIPX_HOME} && \
    mkdir /env && \
    echo "$PIPX_BIN_DIR" > /env/pipx.path

# ansible and its dependencies, related apps and collections
# hadolint ignore=SC2046
RUN --mount=type=bind,source=./packages,target=/packages \
    --mount=type=cache,target=/root/.cache/pip,id=ansible-cache-${TARGETARCH} \
    --mount=type=tmpfs,target=/var/cache/python \
    --mount=type=tmpfs,target=/tmp \
    # ----------------------------------------------------------------------------------------------------
    # ansible related apps
    pipx inject ansible-core --include-apps $(grep -v '^#' /packages/ansible-dependent-app-requirements.txt) && \
    # ----------------------------------------------------------------------------------------------------
    # ansible dependent packages
    pipx inject ansible-core $(grep -v '^#' /packages/ansible-dependency-requirements.txt) && \
    # ----------------------------------------------------------------------------------------------------
    # ansible collections
    mkdir -p /opt/ansible/collections && \
    ansible-galaxy collection install -p /opt/ansible/collections -r /packages/requirements.yaml && \
    # ----------------------------------------------------------------------------------------------------
    chown -R root:coder ${PIPX_HOME} && \
    chmod -R g+rw ${PIPX_HOME} && \
    chown -R root:coder /opt/ansible && \
    find /opt/ansible -type d -exec chmod g+rwx {} + && \
    echo 'ANSIBLE_COLLECTIONS_PATH="$HOME/.ansible/collections:/opt/ansible/collections:/usr/share/ansible/collections"' > /env/ansible.env


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
COPY --from=python-packages /opt/pipx /opt/pipx
COPY --from=python-packages /opt/ansible /opt/ansible

# copy binaries
COPY --from=binary-downloads /usr/local/sbin/* /usr/local/sbin/
COPY --from=github-release-downloads /usr/local/sbin/* /usr/local/sbin/
COPY --from=sdk-rust-cargo /usr/local/bin/* /usr/local/sbin/
COPY --from=sdk-golang /usr/local/bin/* /usr/local/sbin/

# copy environment variables
RUN --mount=type=bind,from=sdk-nodejs,source=/env,target=/env/sdk-nodejs \
    --mount=type=bind,from=sdk-golang,source=/env,target=/env/sdk-golang \
    --mount=type=bind,from=sdk-terraform,source=/env,target=/env/sdk-terraform \
    --mount=type=bind,from=sdk-rust-cargo,source=/env,target=/env/sdk-rust-cargo \
    --mount=type=bind,from=python-packages,source=/env,target=/env/python-packages \
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

# shell initialization scripts
COPY --link --chown=root:root --chmod=644 shell/bash_aliases.defaults /etc/bash_aliases.defaults
COPY --link --chown=root:root --chmod=644 shell/bash_completion.defaults /etc/bash_completion.defaults
COPY --link --chown=root:root --chmod=644 shell/bashrc.defaults /etc/bashrc.defaults
COPY --link --chown=root:root --chmod=644 shell/bashrc /etc/skel/.bashrc
COPY --link --chown=root:root --chmod=644 shell/bashrc.extra /etc/skel/.bashrc.extra

# coder initialization scripts
RUN mkdir -p /opt/coder/bin
COPY --link --chown=root:root --chmod=755 coder/*.sh /opt/coder/bin/

RUN rm -f /etc/apt/apt.conf.d/keep-cache

# Add `coder` user (coder platform will connect the user in as this user)
RUN useradd coder --no-create-home --shell /bin/bash -g coder --groups sudo,docker
USER coder
WORKDIR /
