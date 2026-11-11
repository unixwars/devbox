FROM debian:stable-slim

ARG USERNAME=dev
ARG UID=1000
ARG GID=1000

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

# Package lists are kept on purpose: command-not-found builds its database from them.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash-completion ca-certificates command-not-found curl git gh jq less mc \
      nano nmap openssh-client procps python3 python3-venv ripgrep sudo unzip wget \
 && rm -rf /var/cache/apt/archives

RUN groupadd -g "$GID" "$USERNAME" \
 && useradd -m -u "$UID" -g "$GID" -s /bin/bash "$USERNAME" \
 && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
 && chmod 440 /etc/sudoers.d/$USERNAME

# Mount points for the named volumes. Created here, owned by the user, so a fresh
# volume inherits that ownership on first use.
RUN install -d -o "$USERNAME" -g "$USERNAME" \
      /home/$USERNAME/.claude /home/$USERNAME/.agents /home/$USERNAME/.cache /home/$USERNAME/.npm \
 && install -d -m 700 -o "$USERNAME" -g "$USERNAME" /home/$USERNAME/.secrets

# Interactive shells: tab completion and "did you mean to install ...?" hints.
COPY bashrc-extra.sh /tmp/bashrc-extra.sh
RUN cat /tmp/bashrc-extra.sh >> /etc/bash.bashrc && rm /tmp/bashrc-extra.sh

USER $USERNAME
WORKDIR /workspaces
