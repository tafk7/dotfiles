#!/bin/bash

# Display tmux help and cheat sheet
help-tmux() {
    cat << 'EOF'
Tmux Cheat Sheet - Common Commands

PREFIX KEY: Ctrl-a (instead of default Ctrl-b)

SESSIONS:
  tmux                    Create new session
  tmux new -s name        Create new named session
  tmux ls                 List sessions
  tmux attach -t name     Attach to named session
  tmux kill-session -t name   Kill named session

WINDOWS (within tmux):
  Ctrl-a c               Create new window
  Ctrl-a n               Next window
  Ctrl-a p               Previous window
  Ctrl-a w               List windows
  Ctrl-a &               Kill current window
  Ctrl-a ,               Rename current window

PANES:
  Ctrl-a |               Split vertically
  Ctrl-a -               Split horizontally
  Ctrl-a Left/Right/Up/Down   Navigate panes
  Alt-Arrow              Navigate panes (no prefix needed)
  Ctrl-a x               Kill current pane
  Ctrl-a z               Toggle pane zoom

COPY MODE:
  Ctrl-a [               Enter copy mode
  Space                  Start selection (in copy mode)
  Enter                  Copy selection (in copy mode)
  Ctrl-a ]               Paste

OTHER:
  Ctrl-a d               Detach from session
  Ctrl-a r               Reload tmux config
  Ctrl-a ?               Show all key bindings
  Ctrl-a :               Enter command mode

SESSION MANAGEMENT SHORTCUTS:
  tm <name>              Create/attach to named session
  ta <name>              Attach to session
  tl                     List sessions
EOF
}

# Note: Access this function directly with 'help-tmux' command