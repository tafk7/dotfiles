# A bare Ubuntu release with only sudo and a sudo user `test`: what bootstrap.sh meets on a
# fresh machine (no git, no curl, no CA certificates).
ARG BASE
FROM ${BASE}
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends sudo \
 && rm -rf /var/lib/apt/lists/* \
 && (userdel -r ubuntu 2>/dev/null || true) \
 && useradd -m -s /bin/bash test \
 && echo 'test ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/test && chmod 0440 /etc/sudoers.d/test
