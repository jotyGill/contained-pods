
FROM ubuntu:26.04

ARG THE_USER_NAME=appuser
ARG THE_USER_UID=1000
ARG THE_USER_GID=1000
ARG USER_PASSWORD=

LABEL maintainer="contained-pods"

ENV DEBIAN_FRONTEND=noninteractive

# Copy SSH config template and authorized_keys
COPY sshd_config.template /tmp/sshd_config.template
COPY authorized_keys /tmp/authorized_keys

# Install minimal system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        git \
        openssh-server \
        nano \
        zsh \
        wget \
        ca-certificates \
        gettext-base \
        autoconf \
        build-essential \
        nodejs \
        npm \
        bat \
        sudo \
        fd-find \
        fzf \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        python3-pytest \
        python3-requests \
        python3-virtualenv \
        python3-yaml \
        python3-dotenv \
        python3-mypy \
    && rm -rf /var/lib/apt/lists/* && \
    ln -s $(which fdfind) /usr/local/bin/fd

# Install ripgrep (specific version via .deb)
RUN curl -LO https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep_14.1.1-1_amd64.deb && \
    dpkg -i ripgrep_14.1.1-1_amd64.deb && \
    rm ripgrep_14.1.1-1_amd64.deb

# Create user and set password from build arg
RUN USER_TO_DELETE=$(getent passwd ${THE_USER_UID} | cut -d: -f1) && \
    if [ -n "${USER_TO_DELETE}" ]; then \
        userdel -r ${USER_TO_DELETE} 2>/dev/null || true; \
        groupdel ${USER_TO_DELETE} 2>/dev/null || true; \
    fi && \
    groupadd -g ${THE_USER_GID} ${THE_USER_NAME} && \
    useradd -m -d "/home/${THE_USER_NAME}" -s /bin/bash -u ${THE_USER_UID} -g ${THE_USER_GID} ${THE_USER_NAME} && \
    echo "${THE_USER_NAME}:${USER_PASSWORD}" | chpasswd

# Setup SSH and generate host keys (must be done as root during build)
RUN mkdir -p /var/run/sshd /etc/ssh /home/${THE_USER_NAME}/.ssh && \
    ssh-keygen -A && \
    cat /tmp/sshd_config.template \
    | envsubst '$THE_USER_NAME' \
    | tee /etc/ssh/sshd_config.d/sshd.conf \
    && cat /tmp/authorized_keys \
    | tee /home/${THE_USER_NAME}/.ssh/authorized_keys \
    && rm /tmp/sshd_config.template /tmp/authorized_keys && \
    chmod 700 /home/${THE_USER_NAME}/.ssh && \
    chmod 600 /home/${THE_USER_NAME}/.ssh/authorized_keys && \
    chown -R ${THE_USER_NAME}:${THE_USER_NAME} /home/${THE_USER_NAME}/.ssh

# Install application (customize this section for your needs)
USER ${THE_USER_NAME}
WORKDIR /home/${THE_USER_NAME}

# Create projects directory
USER root

# Add user to sudo group and configure sudoers (password required for sudo)
RUN groupadd -f sudo && \
    usermod -aG sudo ${THE_USER_NAME} && \
    echo "${THE_USER_NAME} ALL=(ALL) ALL" > /etc/sudoers.d/${THE_USER_NAME} && \
    chmod 440 /etc/sudoers.d/${THE_USER_NAME}

# Copy DNS isolation entrypoint script
COPY set-proxy-dns.sh /usr/local/bin/set-proxy-dns.sh
RUN chmod +x /usr/local/bin/set-proxy-dns.sh

# Expose SSH port (standard)
EXPOSE 22

# Start SSH daemon via DNS isolation entrypoint
USER root
ENTRYPOINT ["/usr/local/bin/set-proxy-dns.sh", "/usr/sbin/sshd", "-D"]
