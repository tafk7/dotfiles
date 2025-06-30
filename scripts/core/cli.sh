#!/bin/bash
# CLI argument parsing and help system

# Parse command line arguments
parse_arguments() {
    INSTALL_WORK=false
    INSTALL_PERSONAL=false
    INSTALL_AI=false
    FORCE_MODE=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --work) INSTALL_WORK=true; shift ;;
            --personal) INSTALL_PERSONAL=true; shift ;;
            --ai) INSTALL_AI=true; shift ;;
            --force) FORCE_MODE=true; shift ;;
            -h|--help) 
                show_help
                exit 0 
                ;;
            *) 
                echo "Unknown option: $1"
                show_usage
                exit 1 
                ;;
        esac
    done
}

# Show usage information
show_usage() {
    echo "Usage: $0 [--work] [--personal] [--ai] [--force]"
}

# Show detailed help
show_help() {
    cat << 'EOF'
Dotfiles Installation Script

USAGE:
    ./install.sh [OPTIONS]

OPTIONS:
    --work          Install work-specific tools (VS Code, Azure CLI, etc.)
    --personal      Install personal tools (ffmpeg, etc.)
    --ai            Install AI tools (Claude Code and custom prompts)
    --force         Force installation, backup existing files
    -h, --help      Show this help message

EXAMPLES:
    ./install.sh                    # Basic installation
    ./install.sh --work            # Include work tools
    ./install.sh --work --personal # Complete installation
    ./install.sh --force           # Force overwrite existing configs

DESCRIPTION:
    Installs a modern Linux development environment with:
    - Cross-distribution package management (apt/dnf/pacman)
    - Modern CLI tools (eza, bat, fzf, ripgrep)
    - Development essentials (Docker, Node.js, Python, Git)
    - WSL integration (when applicable)
    - Security-focused configuration management

EOF
}