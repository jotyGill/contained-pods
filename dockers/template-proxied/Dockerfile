FROM localhost/contained-pods:latest

# Build argument for proxy hostname (per-variant, e.g. agents-contained-proxy)
ARG PROXY_HOSTNAME=${VARIANT}-contained-proxy

USER root

# MODIFY PACKAGES AS NEEDED
#RUN npm install -g opencode-ai
#RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent

# Write proxy variables to profile.d so SSH sessions pick them up
# 2. Bash/Zsh/Sh login shells (/etc/profile.d)
RUN PROXY="http://${PROXY_HOSTNAME}:3128" && \
    echo "export http_proxy=$PROXY" > /etc/profile.d/proxy.sh && \
    echo "export https_proxy=$PROXY" >> /etc/profile.d/proxy.sh && \
    echo 'export no_proxy=localhost,127.0.0.1' >> /etc/profile.d/proxy.sh && \
    echo "export HTTP_PROXY=$PROXY" >> /etc/profile.d/proxy.sh && \
    echo "export HTTPS_PROXY=$PROXY" >> /etc/profile.d/proxy.sh && \
    echo 'export NO_PROXY=localhost,127.0.0.1' >> /etc/profile.d/proxy.sh

# 3. Csh/Tcsh login shells
RUN PROXY="http://${PROXY_HOSTNAME}:3128" && \
    echo "setenv http_proxy $PROXY" > /etc/profile.d/proxy.csh && \
    echo "setenv https_proxy $PROXY" >> /etc/profile.d/proxy.csh && \
    echo 'setenv no_proxy localhost,127.0.0.1' >> /etc/profile.d/proxy.csh && \
    echo "setenv HTTP_PROXY $PROXY" >> /etc/profile.d/proxy.csh && \
    echo "setenv HTTPS_PROXY $PROXY" >> /etc/profile.d/proxy.csh && \
    echo 'setenv NO_PROXY localhost,127.0.0.1' >> /etc/profile.d/proxy.csh

# 5. Non-shell system tools (reads /etc/environment)
RUN PROXY="http://${PROXY_HOSTNAME}:3128" && \
    echo "http_proxy=$PROXY" >> /etc/environment && \
    echo "https_proxy=$PROXY" >> /etc/environment && \
    echo 'no_proxy=localhost,127.0.0.1' >> /etc/environment && \
    echo "HTTP_PROXY=$PROXY" >> /etc/environment && \
    echo "HTTPS_PROXY=$PROXY" >> /etc/environment && \
    echo 'NO_PROXY=localhost,127.0.0.1' >> /etc/environment

# 6. Allow proxy env vars to persist when using sudo
RUN echo 'Defaults env_keep += "http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY"' > /etc/sudoers.d/proxy && \
    chmod 0440 /etc/sudoers.d/proxy

USER appuser
SHELL ["/bin/bash", "-c"]

# Add ~/.local/bin to PATH
RUN echo 'export PATH=$HOME/.local/bin:$PATH' >> ~/.bashrc && \
    echo 'export PATH=$HOME/.local/bin:$PATH' >> ~/.zshrc

# Switch back to root for SSH daemon (entrypoint from base image)
USER root
