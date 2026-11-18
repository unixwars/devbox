FROM debian:stable-slim

ARG USERNAME=dev
ARG UID=1000
ARG GID=1000

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

# Package lists are kept on purpose: command-not-found builds its database from them.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash-completion ca-certificates command-not-found curl git gh jq less mc \
      nano nmap openssh-client postgresql postgresql-client procps python3 python3-venv ripgrep sudo unzip wget \
      fonts-liberation fonts-noto-color-emoji libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 \
      libcairo2 libcups2t64 libdbus-1-3 libdrm2 libgbm1 libglib2.0-0t64 libnspr4 libnss3 \
      libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 libxfixes3 \
      libxkbcommon0 libxrandr2 \
 && rm -rf /var/cache/apt/archives

RUN groupadd -g "$GID" "$USERNAME" \
 && useradd -m -u "$UID" -g "$GID" -s /bin/bash "$USERNAME" \
 && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
 && chmod 440 /etc/sudoers.d/$USERNAME

# Mount points for the named volumes. Created here, owned by the user, so a fresh
# volume inherits that ownership on first use.
RUN install -d -o "$USERNAME" -g "$USERNAME" \
      /home/$USERNAME/.claude /home/$USERNAME/.agents /home/$USERNAME/.cache /home/$USERNAME/.npm

# Interactive shells: tab completion and "did you mean to install ...?" hints.
COPY bashrc-extra.sh /tmp/bashrc-extra.sh
RUN cat /tmp/bashrc-extra.sh >> /etc/bash.bashrc && rm /tmp/bashrc-extra.sh

# Pinned sops + age for the secrets workflow (checksums verified in the script).
COPY install-sops-age.sh /tmp/install-sops-age.sh
RUN bash /tmp/install-sops-age.sh /usr/local/bin && rm /tmp/install-sops-age.sh
# Pinned Stripe CLI (checksum verified in the script).
COPY install-stripe-cli.sh /tmp/install-stripe-cli.sh
RUN bash /tmp/install-stripe-cli.sh /usr/local/bin && rm /tmp/install-stripe-cli.sh
COPY bin/devbox-pg /usr/local/bin/devbox-pg
COPY bin/with-secrets /usr/local/bin/with-secrets
RUN chmod 755 /usr/local/bin/with-secrets

USER $USERNAME
WORKDIR /workspaces
