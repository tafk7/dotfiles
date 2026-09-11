# Compatibility boundary

The theme reader temporarily accepts legacy `generated/theme.sh` and
`generated/theme-overrides.sh` files created by pre-state-schema releases. The
reader is owned by `lib/theme-resolve.sh`; it is read-only during shell startup.

This compatibility path can be removed after every supported machine has run
`bin/theme-switcher --init` once and has a valid
`${XDG_STATE_HOME:-~/.local/state}/dotfiles/theme.tsv`. The migration behavior
is covered by `tests/theme-system.sh`.
