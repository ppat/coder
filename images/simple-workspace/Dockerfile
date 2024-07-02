FROM ubuntu:jammy@sha256:340d9b015b194dc6e2a13938944e0d016e57b9679963fdeb9ce021daac430221

# shell options to ensure RUN statements fail on error
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# minimum requirements for running coder agent
RUN apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends \
      bash \
      curl \
      git \
      sudo \
      unzip \
      wget && \
    apt-get autoremove -y && \
    apt-get clean -y && \
    apt-get autoremove -y && \
    apt-get clean -y && \
    rm -rf /tmp/* /var/cache/debconf/* /var/cache/python/* /var/lib/apt/lists/* /var/log/* /var/tmp/*

ARG USER=coder
RUN useradd --groups sudo --no-create-home --shell /bin/bash ${USER} \
	&& echo "${USER} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/${USER} \
	&& chmod 0440 /etc/sudoers.d/${USER}
USER ${USER}
WORKDIR /home/${USER}
