#!/bin/bash
# Dotfiles Cheat Sheet - Quick reference for all keybindings and shortcuts
# Part of dotfiles - compact display of vim, tmux, git, and shell shortcuts

set -e

# Source core functions for colors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Navigate up two directories since we're now in scripts/utils/
DOTFILES_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$DOTFILES_DIR/lib/core.sh"

# Terminal width detection
TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)

# Color definitions using tput for better compatibility
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
    BOLD=$(tput bold)
    CYAN=$(tput setaf 6)
    YELLOW=$(tput setaf 3)
    DIM=$(tput dim)
    RESET=$(tput sgr0)
else
    BOLD=""
    CYAN=""
    YELLOW=""
    DIM=""
    RESET=""
fi

# Print section header
print_header() {
    local title="$1"
    echo
    echo "${BOLD}${CYAN}${title}${RESET}"
}

# Print table separator
print_separator() {
    printf "${DIM}"
    printf '─%.0s' $(seq 1 "$TERM_WIDTH")
    printf "${RESET}\n"
}

# Format keybinding line with colors
format_line() {
    echo "$1" | sed -E "s/([^ ]+)( +)([^│]+)/\\1\\2${DIM}\\3${RESET}/g" | \
                sed -E "s/^([^ ]+)/    ${YELLOW}\\1${RESET}/"
}

# Show vim keybindings
show_vim() {
    print_header "VIM KEYBINDINGS"
    echo "    Navigation          Git                Code               Windows"
    print_separator
    format_line "Ctrl+P  Files       ,gs  Status        ,af  Fix          Ctrl+E  Up"
    format_line ",f      Files       ,gd  Diff          ,an  Next err     Ctrl+S  Left"
    format_line ",b      Buffers     ,gb  Blame         ,ap  Prev err     Ctrl+D  Down"
    format_line ",g      Grep        ,hn  Next hunk     ,/   Comment      Ctrl+F  Right"
    format_line "Space   Clear hl    ,hs  Stage hunk    ,n   Line nums    "
    format_line "jk      Escape      ,hu  Undo hunk     ,ss  Strip space  "
    echo
    echo "    Text Manipulation   File Operations    FZF Tips           Misc"
    print_separator
    format_line "cs\"'    \" → '       ,w   Save (force)  Ctrl+/  Preview    ,q   Quit"
    format_line "ds\"     Delete \"    ,Q   Quit all      Tab     Multi-sel  ,Q   Quit all"
    format_line "ysiw\"   Add \"       :w   Save          Enter   Open       u    Undo"
    format_line "gc      Comment     :q   Quit                             .    Repeat"
}

# Show tmux keybindings
show_tmux() {
    print_header "TMUX KEYBINDINGS (Prefix: Ctrl+a)"
    echo "    Panes               Windows            Sessions           Config"
    print_separator
    format_line "|    Split horiz    c    New           d    Detach       r    Reload"
    format_line "-    Split vert     1-9  Switch        s    List         ?    Show keys"
    format_line "x    Kill pane      n    Next          $    Rename       "
    format_line "X    Kill window    p    Previous      (    Previous     "
    echo
    echo "    Navigation (No Prefix)              Resizing (With Prefix)"
    print_separator
    format_line "Alt+E    Up         Alt+1-9  Window   Shift+↑    Up 5    E    Up 5"
    format_line "Alt+S    Left                         Shift+←    Left 5  S    Left 5"
    format_line "Alt+D    Down                         Shift+↓    Down 5  D    Down 5"
    format_line "Alt+F    Right                        Shift+→    Right 5 F    Right 5"
}

# Show git aliases
show_git() {
    print_header "GIT ALIASES"
    echo "    Status              Commits            Branches           History"
    print_separator
    format_line "gs   status         gc   commit        gb   branch        gl   log graph"
    format_line "ga   add            gcm  commit -m     gco  checkout      gla  log all"
    format_line "gaa  add all        gca  amend         gcb  new branch    "
    format_line "gd   diff           gp   push          gpl  pull          "
    format_line "gdc  diff cached    gpu  push upstream gstash stash       "
    echo
    echo "    Functions                            Usage"
    print_separator
    format_line "gundo              Undo last commit (keep changes)"
    format_line "gquick \"message\"   Add all, commit, and push"
}

# Show shell shortcuts
show_shell() {
    print_header "SHELL ALIASES & SHORTCUTS"
    echo "    Navigation          File Operations    System Info        Network"
    print_separator
    format_line "..   Parent dir     ls   List (eza)    df   Disk free     myip    Public IP"
    format_line "...  Up 2 dirs      ll   Long list     du   Disk usage    localip Local IP"
    format_line "~    Home dir       la   All files     free Memory        ports   Open ports"
    format_line "-    Previous dir   tree Tree view     psg  Find process  note    Quick notes"
    echo
    echo "    Modern Tools        Archive            Dotfiles           FZF Extras"
    print_separator
    format_line "bat  Better cat     untar Extract      reload   Reload    fgb    Git branch"
    format_line "fd   Find files     tarc  Create tar   themes   List      fgl    Git log"
    format_line "rg   Ripgrep        fr    Find/replace theme-switch       frg    Ripgrep+fzf"
    format_line "vim  Neovim         extract Archive     update-configs    fp     Projects"
    echo
    echo "    Tmux Shortcuts      Safer Commands     Quick Actions      Claude"
    print_separator
    format_line "tm   New session    rmff Force remove  psmem  Sort by RAM   cl     New"
    format_line "ta   Attach         rmi  Interactive   pscpu  Sort by CPU   clc    Continue"
    format_line "tl   List sessions  cpv  Verbose copy  ducks  Large files   clp    Print"
    format_line "tk   Kill session   rmv  Verbose rm    md     View markdown cheat  Help"
}

# Show development tools
show_dev() {
    print_header "DEVELOPMENT SHORTCUTS"
    echo "    Python              Node.js            Docker             General"
    print_separator
    format_line "py   Python3        ni   npm install   dps  List          vimvim Real vim"
    format_line "venv Create venv    nr   npm run      di   Images        vivim  Real vi"
    format_line "activate Activate   nrd  npm run dev  dc   Compose       fr     Find/replace"
    format_line "pytest Run tests    nrb  npm run build dcu  Up           "
    format_line "fmt  Black format   nrt  npm run test  dcd  Down         "
    format_line "lint Ruff check     nclean Reinstall   dprune Clean       "
}

# Show all cheatsheets
show_all() {
    show_vim
    show_tmux
    show_git
    show_shell
    show_dev
}

# Main function
main() {
    case "${1:-all}" in
        vim)
            show_vim
            ;;
        tmux)
            show_tmux
            ;;
        git)
            show_git
            ;;
        shell)
            show_shell
            ;;
        dev)
            show_dev
            ;;
        all|"")
            show_all
            ;;
        *)
            echo "Usage: cheat [vim|tmux|git|shell|dev|all]"
            echo "Show keybindings and shortcuts for dotfiles tools"
            exit 1
            ;;
    esac
}

# Handle piping to less for long output
if [[ -t 1 ]] && [[ "${1:-all}" == "all" ]]; then
    # Output is to terminal and showing all sections
    main "$@" | less -R
else
    # Output is piped or showing single section
    main "$@"
fi