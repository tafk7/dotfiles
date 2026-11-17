# A clean Ubuntu release with only what dotfiles' CI adds before its install job: the
# bootstrap prerequisites and a sudo user `test` (setup.sh refuses to run as root).
ARG BASE
FROM ${BASE}
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl git sudo locales lsb-release passwd \
 && rm -rf /var/lib/apt/lists/* \
 && (userdel -r ubuntu 2>/dev/null || true) \
 && useradd -m -s /bin/bash test \
 && echo 'test ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/test && chmod 0440 /etc/sudoers.d/test
