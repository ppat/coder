FROM ubuntu:jammy@sha256:19478ce7fc2ffbce89df29fea5725a8d12e57de52eb9ea570890dc5852aac1ac

# shell options to ensure RUN statements fail on error
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

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
    echo 'PYTHONPYCACHEPREFIX=/var/cache/python' >> /etc/environment

# minimum requirements for homelab workspace
RUN apt-get update && \
    # minimum requirements for coder agent (from https://github.com/coder/enterprise-images/blob/main/images/base/Dockerfile.ubuntu)
    DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends \
      bash \
      curl \
      git \
      sudo \
      unzip \
      wget \
      && \
    # minimum requirements for homelab workspace environment
    DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends \
      apt-transport-https \
      build-essential \
      ca-certificates \
      gnupg \
      locales \
      man \
      python3 \
      python3-pip \
      software-properties-common \
      && \
    # Install latest Git using their official PPA
    add-apt-repository ppa:git-core/ppa && \
    DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends git && \
    # ----------------------------------------------------------------------------------------------------
    # systemd requirements (from https://github.com/nestybox/dockerfiles/blob/master/ubuntu-jammy-systemd/Dockerfile)
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
      sys-kernel-tracing.mount && \
    # ----------------------------------------------------------------------------------------------------
    apt-get autoremove -y && \
    apt-get clean -y && \
    apt-get autoremove -y && \
    apt-get clean -y && \
    find /usr -name __pycache__ -exec rm -rf {} + && \
    rm -rf /tmp/* /var/cache/debconf/* /var/cache/python/* /var/lib/apt/lists/* /var/log/* /var/tmp/*

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
# this will be utilized in subsequent child images at each stage
# renovate: datasource=github-releases depName=upx/upx
ARG UPX_VERSION="4.2.4"
WORKDIR /tmp
RUN wget  --progress=dot:giga https://github.com/upx/upx/releases/download/v${UPX_VERSION}/upx-${UPX_VERSION}-amd64_linux.tar.xz -O /tmp/upx.tar.xz && \
    xz -d /tmp/upx.tar.xz && \
    tar xvf upx.tar -C /usr/local/sbin --strip-components 1 upx-${UPX_VERSION}-amd64_linux/upx && \
    rm -rf /var/log/* /tmp/* /var/tmp/*

# install docker-engine
# hadolint ignore=SC1091
RUN \
    # ----------------------------------------------------------------------------------------------------
    # prep apt source for docker
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo \
      "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    # ----------------------------------------------------------------------------------------------------
    # install docker
    apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install --yes --no-install-recommends \
      containerd.io  \
      docker-ce \
      docker-ce-cli \
      docker-ce-rootless-extras \
      docker-buildx-plugin \
      docker-compose-plugin \
      docker-scan-plugin \
    && \
    # ----------------------------------------------------------------------------------------------------
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
      /usr/libexec/docker/cli-plugins/docker-compose \
      /usr/libexec/docker/cli-plugins/docker-scan \
    && \
    # ----------------------------------------------------------------------------------------------------
    apt-get autoremove -y && \
    apt-get clean -y && \
    find /usr -name __pycache__ -exec rm -rf {} + && \
    rm -rf /tmp/* /var/cache/debconf/* /var/cache/python/* /var/lib/apt/lists/* /var/log/* /var/tmp/*

# enables docker starting with systemd
RUN systemctl enable docker
WORKDIR /tmp

# system packages
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -yq \
      autoconf \
      bash-completion \
      bat \
      bsdextrautils \
      cron \
      dnsutils \
      fd-find \
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
      jq \
      jsonnet \
      ldap-utils \
      less \
      libarchive-dev \
      libarchive-tools \
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
      upx-ucl \
      vim \
      watch \
      xz-utils \
      zip \
      zsh \
      zstd \
    && \
    # ----------------------------------------------------------------------------------------------------
    apt-get autoremove -y && \
    apt-get clean -y && \
    find /usr -name __pycache__ -exec rm -rf {} + && \
    rm -rf /tmp/* /var/cache/debconf/* /var/cache/python/* /var/lib/apt/lists/* /var/log/* /var/tmp/*

# unminimize
RUN sed -i 's|xargs dpkg -S|xargs -r dpkg -S|g' /usr/local/sbin/unminimize && \
    echo -e 'y\ny' | unminimize

# NodeJS/NPM/NPX: install latest LTS version
# renovate: datasource=node depName=node versioning=node
ARG NODE_VERSION="20.14.0"
ENV FNM_ROOT=/opt/fnm
ENV PATH="$PATH:${FNM_ROOT}"
RUN mkdir -p /opt/fnm && \
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell --install-dir ${FNM_ROOT} && \
    eval "$(${FNM_ROOT}/fnm env --shell bash --use-on-cd --fnm-dir ${FNM_ROOT})" && \
    ${FNM_ROOT}/fnm install ${NODE_VERSION} && \
    ${FNM_ROOT}/fnm use ${NODE_VERSION} && \
    ${FNM_ROOT}/fnm default --fnm-dir ${FNM_ROOT} ${NODE_VERSION} && \
    chown -R root:coder ${FNM_ROOT} && \
    chmod -R g+rw ${FNM_ROOT} && \
    chmod 755 ${FNM_ROOT}/fnm && \
    mv /etc/environment /tmp/env.tmp && \
    grep -v '^PATH=' /tmp/env.tmp > /etc/environment && \
    echo "PATH=\"${PATH}\"" >> /etc/environment && \
    echo "FNM_ROOT=\"${FNM_ROOT}\"" >> /etc/environment && \
    # ----------------------------------------------------------------------------------------------------
    rm -rf /var/log/* /tmp/* /var/tmp/*

# NodeJS based tooling
COPY packages/npm-packages.json /tmp/npm-packages.json
# hadolint ignore=DL3016,SC2086
RUN eval "$(${FNM_ROOT}/fnm env --shell bash --use-on-cd --fnm-dir ${FNM_ROOT})" && \
    ${FNM_ROOT}/fnm use ${NODE_VERSION} && \
    npm config set update-notifier false && \
    npm config set fund false && \
    npm config set loglevel error && \
    for i in $(cat /tmp/npm-packages.json | jq -r '.devDependencies | to_entries | map([.key, .value] | join("@")) | .[]'); do echo $i; npm install -g $i; done && \
    chown -R root:coder ${FNM_ROOT} && \
    chmod -R g+rw ${FNM_ROOT} && \
    # ----------------------------------------------------------------------------------------------------
    rm -rf /var/log/* /tmp/* /var/tmp/*

# Golang (as per official instructions from https://go.dev/doc/install)
# renovate: datasource=golang-version depName=golang
ARG GOLANG_VERSION="1.22.4"
ENV GOROOT="/usr/local/go"
ENV PATH="$PATH:$GOROOT/bin"
RUN wget --progress=dot:giga "https://go.dev/dl/go${GOLANG_VERSION}.linux-amd64.tar.gz" -O /tmp/golang.tar.gz && \
    tar -C /usr/local -xzf /tmp/golang.tar.gz && \
    export GOPATH="/usr/local/go" && \
    go install golang.org/x/lint/golint@latest && \
    go install github.com/uudashr/gopkgs/v2/cmd/gopkgs@latest && \
    unset GOPATH && \
    mv /etc/environment /tmp/env.tmp && \
    grep -v '^PATH=' /tmp/env.tmp > /etc/environment && \
    echo "PATH=\"${PATH}\"" >> /etc/environment && \
    echo "GOROOT=\"${GOROOT}\"" >> /etc/environment && \
    # ----------------------------------------------------------------------------------------------------
    rm -rf /var/log/* /tmp/* /var/tmp/*

# python build and lint tools: (poetry, etc)
ENV PIPX_HOME=/opt/pipx
ENV PIPX_BIN_DIR=/usr/local/bin
COPY packages/pipx-package-requirements.txt /tmp/pipx-package-requirements.txt
# hadolint ignore=DL3013,SC2086
RUN mkdir ${PIPX_HOME} && \
    for t in $(grep -v '^#' /tmp/pipx-package-requirements.txt); do pipx install ${t}; done && \
    chown -R root:coder ${PIPX_HOME} && \
    chmod -R g+rw ${PIPX_HOME} && \
    find /usr -name __pycache__ -exec rm -rf {} + && \
    find /opt -name __pycache__ -exec rm -rf {} + && \
    rm -rf /tmp/* /var/cache/python/* /var/log/* /var/tmp/*

# ansible dependencies, related apps and collections
ENV ANSIBLE_COLLECTIONS_PATH="/opt/ansible/collections:/usr/share/ansible/collections"
COPY packages/ansible-* /tmp/
COPY packages/requirements.yaml /tmp/ansible-galaxy.yaml
# hadolint ignore=SC2046
RUN \
    # ----------------------------------------------------------------------------------------------------
    # ansible related apps
    pipx inject ansible-core --include-apps $(grep -v '^#' /tmp/ansible-dependent-app-requirements.txt) && \
    # ----------------------------------------------------------------------------------------------------
    # ansible dependent packages
    pipx inject ansible-core $(grep -v '^#' /tmp/ansible-dependency-requirements.txt) && \
    # ----------------------------------------------------------------------------------------------------
    # ansible collections
    mkdir -p /opt/ansible/collections && \
    ansible-galaxy collection install -p /opt/ansible/collections -r /tmp/ansible-galaxy.yaml && \
    # ----------------------------------------------------------------------------------------------------
    chown -R root:coder ${PIPX_HOME} && \
    chmod -R g+rw ${PIPX_HOME} && \
    chown -R root:coder /opt/ansible && \
    find /opt/ansible -type d -exec chmod g+rwx {} + && \
    echo "ANSIBLE_COLLECTIONS_PATH=\"${ANSIBLE_COLLECTIONS_PATH}\"" >> /etc/environment && \
    # ----------------------------------------------------------------------------------------------------
    find /usr -name __pycache__ -exec rm -rf {} + && \
    find /opt -name __pycache__ -exec rm -rf {} + && \
    rm -rf /tmp/* /var/cache/python/* /var/log/* /var/tmp/*

# tfenv + terraform
# renovate: datasource=github-releases depName=tfutils/tfenv
ARG TFENV_VERSION="3.0.0"
# renovate: datasource=github-releases depName=hashicorp/terraform
ARG TERRAFORM_VERSION="1.8.5"
ENV PATH="${PATH}:/opt/tfenv/bin"
RUN git clone -b "v${TFENV_VERSION}" --depth=1 https://github.com/tfutils/tfenv.git /opt/tfenv 2> /dev/null && \
    tfenv install ${TERRAFORM_VERSION} && \
    tfenv use ${TERRAFORM_VERSION} && \
    upx /opt/tfenv/versions/${TERRAFORM_VERSION}/terraform && \
    chown -R root:coder /opt/tfenv && \
    chmod -R g+rw /opt/tfenv && \
    mv /etc/environment /tmp/env.tmp && \
    grep -v '^PATH=' /tmp/env.tmp > /etc/environment && \
    echo "PATH=\"${PATH}\"" >> /etc/environment && \
    rm -rf /var/log/* /tmp/* /var/tmp/*

# kubectl version=latest(intersect(stable-channel(https://github.com/k3s-io/k3s/releases), https://github.com/kubernetes/kubernetes/releases))
# renovate: datasource=github-releases depName=kubernetes/kubernetes
ARG KUBECTL_VERSION="1.30.1"
RUN wget --progress=dot:giga https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl -O /tmp/kubectl && \
    wget --progress=dot:giga https://dl.k8s.io/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256 -O /tmp/kubectl.sha256 && \
    echo "$(cat /tmp/kubectl.sha256)  /tmp/kubectl" | sha256sum --check && \
    install -o root -g root -m 0755 /tmp/kubectl /usr/local/sbin/kubectl && \
    upx /usr/local/sbin/kubectl && \
    rm -rf /tmp/* /var/log/* /var/tmp/*

# helm
# renovate: datasource=github-releases depName=helm/helm
ARG HELM_VERSION="3.15.2"
RUN wget --progress=dot:giga -c https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz -O - | tar -xzv --strip-components 1 -C /tmp && \
    install -o root -g root -m 0755 /tmp/helm /usr/local/sbin/helm && \
    upx /usr/local/sbin/helm && \
    rm -rf /tmp/* /var/log/* /var/tmp/*

# packer
# renovate: datasource=github-releases depName=hashicorp/packer
ARG PACKER_VERSION="1.10.3"
RUN wget --progress=dot:giga -c https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip -O /tmp/packer.zip && \
    unzip /tmp/packer.zip && \
    install -o root -g root -m 0755 /tmp/packer /usr/local/sbin/packer && \
    upx /usr/local/sbin/packer && \
    rm -rf /tmp/* /var/log/* /var/tmp/*

# yq
# renovate: datasource=github-releases depName=mikefarah/yq
ARG YQ_VERSION="4.44.1"
RUN wget --progress=dot:giga -c https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64.tar.gz -O - | tar -xzv -C /tmp && \
    install -o root -g root -m 0755 /tmp/yq_linux_amd64 /usr/local/sbin/yq && \
    upx /usr/local/sbin/yq && \
    rm -rf /tmp/* /var/log/* /var/tmp/*

# fetch (used for installing packages from github release assets)
# renovate: datasource=github-releases depName=gruntwork-io/fetch
ARG FETCH_VERSION="0.4.6"
RUN wget --progress=dot:giga -c https://github.com/gruntwork-io/fetch/releases/download/v${FETCH_VERSION}/fetch_linux_amd64 -O /tmp/fetch_linux && \
    install -o root -g root -m 0755 /tmp/fetch_linux /usr/local/sbin/fetch && \
    upx /usr/local/sbin/fetch && \
    rm -rf /tmp/* /var/log/* /var/tmp/*

# install apps from github releases
COPY packages/github-releases.yaml /tmp/github-releases.yaml
COPY packages/install-from-github-release.sh /tmp/install-from-github-release.sh
ARG FETCH_GH_TOKEN
RUN /bin/bash /tmp/install-from-github-release.sh /tmp/github-releases.yaml

# shell initialization scripts
COPY shell/bash_aliases.defaults /etc/bash_aliases.defaults
COPY shell/bash_completion.defaults /etc/bash_completion.defaults
COPY shell/bashrc.defaults /etc/bashrc.defaults
COPY shell/bashrc /etc/skel/.bashrc

# coder initialization scripts
RUN mkdir -p /opt/coder/bin
COPY coder/*.sh /opt/coder/bin/
RUN chmod -R 755 /opt/coder/bin && \
    chown -R root:root /opt/coder/bin/*

# Add `coder` user (coder platform will connect the user in as this user)
RUN useradd coder --no-create-home --shell /bin/bash -g coder --groups sudo,docker
USER coder
WORKDIR /
