# The image agent scenarios run in: the tools a session needs (Node.js for OpenCode plugin tests)
# and a user who is not root (Claude refuses bypass mode as root). The agent CLIs are not in it: a run mounts the
# binaries it was given, read-only, at /opt/agents (a Codex package directory at /opt/codex).
ARG BASE
FROM ${BASE}
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      python3 git tmux procps ca-certificates curl sudo locales less nodejs \
 && rm -rf /var/lib/apt/lists/* \
 && (userdel -r ubuntu 2>/dev/null || true) \
 && useradd -m -u 1000 -s /bin/bash ada \
 && sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen >/dev/null
ENV LANG=en_US.UTF-8 PATH=/opt/codex/bin:/opt/agents:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
