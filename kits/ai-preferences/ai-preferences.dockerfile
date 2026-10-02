# syntax=docker/dockerfile:1
# Files only: the managed settings land in place, the agent's files are copied
# into its home by the install hook (a volume or another kit may own ~/.claude).
FROM scratch
COPY --chmod=u=rwX,go=rX etc/ /etc/
COPY --chmod=u=rwX,go=rX home/ /usr/share/dotfiles-ai/home/
