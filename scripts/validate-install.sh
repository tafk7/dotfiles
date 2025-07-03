#!/bin/bash
# Installation Validation Script
# Comprehensive testing of dotfiles installation completeness
# Usage: ./scripts/validate-install.sh [--work] [--personal] [--verbose] [--fix] [--help]

set -e

# Get script directory and load libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

# Source required libraries
source "$DOTFILES_DIR/lib/core.sh"
source "$DOTFILES_DIR/lib/validation.sh"

# Configuration flags
VALIDATE_WORK=false
VALIDATE_PERSONAL=false
VERBOSE_MODE=false
FIX_MODE=false
JSON_OUTPUT=false
CATEGORY=""

# Available validation categories
VALID_CATEGORIES=("base" "docker" "work" "personal" "config" "shell" "wsl" "all")

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --work)
                VALIDATE_WORK=true
                shift
                ;;
            --personal)
                VALIDATE_PERSONAL=true
                shift
                ;;
            --verbose|-v)
                VERBOSE_MODE=true
                shift
                ;;
            --fix)
                FIX_MODE=true
                shift
                ;;
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --category)
                CATEGORY="$2"
                if [[ ! " ${VALID_CATEGORIES[*]} " =~ " ${CATEGORY} " ]]; then
                    error "Invalid category: $CATEGORY"
                    error "Valid categories: ${VALID_CATEGORIES[*]}"
                    exit 1
                fi
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help information
show_help() {
    cat << EOF
Installation Validation Script - Comprehensive dotfiles testing

USAGE:
    ./scripts/validate-install.sh [OPTIONS]

OPTIONS:
    --work              Validate work environment packages (Azure CLI, Node.js tools)
    --personal          Validate personal packages (media tools)
    --verbose, -v       Enable verbose output with detailed information
    --fix               Attempt to automatically fix detected issues
    --json              Output results in JSON format for automation
    --category <cat>    Validate specific category only
    --help, -h          Show this help message

CATEGORIES:
    base                Base system packages and tools
    docker              Docker and container tools
    work                Professional development tools
    personal            Media and entertainment tools
    config              Configuration files and symlinks
    shell               Shell environment (Zsh, Oh My Zsh, plugins)
    wsl                 WSL-specific integration
    all                 All categories (default)

EXAMPLES:
    ./scripts/validate-install.sh                    # Basic validation
    ./scripts/validate-install.sh --work --personal  # Full environment validation
    ./scripts/validate-install.sh --verbose          # Detailed output
    ./scripts/validate-install.sh --category docker  # Docker-only validation
    ./scripts/validate-install.sh --fix              # Auto-repair mode
    ./scripts/validate-install.sh --json             # Machine-readable output

EXIT CODES:
    0    All validations passed
    1    Some validations failed
    2    Script error or invalid arguments

EOF
}

# Validate base system packages
validate_base_packages() {
    echo
    test_info "=== VALIDATING BASE PACKAGES ==="
    
    # Build tools
    validate_command "gcc" "GCC compiler" "sudo apt install build-essential"
    validate_command "make" "Make build tool" "sudo apt install build-essential"
    validate_command_with_version "curl" "--version" "cURL"
    validate_command_with_version "wget" "--version" "wget"
    validate_command_with_version "git" "--version" "Git"
    validate_command "unzip" "unzip utility" "sudo apt install unzip"
    validate_command "zip" "zip utility" "sudo apt install zip"
    validate_command_with_version "jq" "--version" "jq JSON processor"
    
    # Shell and modern CLI tools
    validate_command_with_version "zsh" "--version" "Zsh shell"
    validate_command_with_version "nvim" "--version" "Neovim" "sudo apt install neovim"
    
    # Check for bat (Ubuntu package name variations)
    if command_exists bat; then
        validate_command_with_version "bat" "--version" "bat file viewer"
    elif command_exists batcat; then
        validate_command_with_version "batcat" "--version" "bat file viewer (as batcat)"
    else
        test_fail "bat file viewer not found" "sudo apt install bat"
    fi
    
    # Check for fd (Ubuntu package name variations)
    if command_exists fd; then
        validate_command_with_version "fd" "--version" "fd file finder"
    elif command_exists fdfind; then
        validate_command_with_version "fdfind" "--version" "fd file finder (as fdfind)"
    else
        test_fail "fd file finder not found" "sudo apt install fd-find"
    fi
    
    validate_command_with_version "rg" "--version" "ripgrep" "sudo apt install ripgrep"
    
    # Check for eza (may be installed via GitHub)
    if command_exists eza; then
        validate_command_with_version "eza" "--version" "eza file lister"
    else
        test_warn "eza not found" "Installed via GitHub releases or not available"
    fi
    
    # Check for glow (may be installed via snap or GitHub)
    if command_exists glow; then
        validate_command_with_version "glow" "--version" "glow markdown viewer"
    else
        test_warn "glow not found" "Install via snap or GitHub releases"
    fi
    
    # Development essentials
    validate_command_with_version "python3" "--version" "Python 3"
    validate_command_with_version "pip3" "--version" "pip3 package manager"
    
    if command_exists pipx; then
        validate_command_with_version "pipx" "--version" "pipx package manager"
    else
        test_warn "pipx not found" "sudo apt install pipx"
    fi
    
    validate_command_with_version "node" "--version" "Node.js"
    validate_command_with_version "npm" "--version" "npm package manager"
    
    # System utilities
    validate_command "ssh" "SSH client" "sudo apt install openssh-client"
    
    # FZF validation
    validate_fzf_integration
}

# Validate work environment packages
validate_work_packages() {
    echo
    test_info "=== VALIDATING WORK ENVIRONMENT ==="
    
    # Azure CLI
    validate_command_with_version "az" "--version" "Azure CLI" "Install Azure CLI"
    
    # Node.js global packages
    if command_exists npm; then
        validate_npm_global_package "yarn"
        validate_npm_global_package "eslint"
        validate_npm_global_package "prettier"
    else
        test_fail "npm not available - cannot check global packages"
    fi
    
    # Python development tools
    if command_exists pipx; then
        validate_python_package "black" "pipx"
        validate_python_package "ruff" "pipx"
    elif command_exists pip3; then
        validate_python_package "black" "pip"
        validate_python_package "ruff" "pip"
    else
        test_fail "Neither pipx nor pip3 available for Python packages"
    fi
}

# Validate personal environment packages
validate_personal_packages() {
    echo
    test_info "=== VALIDATING PERSONAL ENVIRONMENT ==="
    
    validate_command_with_version "ffmpeg" "-version" "FFmpeg media tool"
    validate_command_with_version "yt-dlp" "--version" "yt-dlp downloader"
}

# Validate configuration files and symlinks
validate_configuration_files() {
    echo
    test_info "=== VALIDATING CONFIGURATION FILES ==="
    
    # Configuration files that should be symlinks
    local config_files=(
        "$HOME/.bashrc:$DOTFILES_DIR/configs/bashrc"
        "$HOME/.zshrc:$DOTFILES_DIR/configs/zshrc"
        "$HOME/.config/nvim/init.vim:$DOTFILES_DIR/configs/init.vim"
        "$HOME/.tmux.conf:$DOTFILES_DIR/configs/tmux.conf"
        "$HOME/.editorconfig:$DOTFILES_DIR/configs/editorconfig"
        "$HOME/.profile:$DOTFILES_DIR/configs/profile"
        "$HOME/.ripgreprc:$DOTFILES_DIR/configs/ripgreprc"
    )
    
    for mapping in "${config_files[@]}"; do
        local link="${mapping%:*}"
        local target="${mapping#*:}"
        local name=$(basename "$link")
        
        validate_symlink "$link" "$target" "$name configuration"
    done
    
    # Git config should exist but not be a symlink (it's templated)
    if validate_file_exists "$HOME/.gitconfig" "Git configuration"; then
        if [[ -L "$HOME/.gitconfig" ]]; then
            test_warn "Git config is a symlink (should be a templated file)"
        else
            test_pass "Git config is a templated file (correct)"
            
            # Check if it contains actual values (not template placeholders)
            if grep -q "{{GIT_NAME}}" "$HOME/.gitconfig" 2>/dev/null; then
                test_fail "Git config contains template placeholders" "Re-run installer to fill in git details"
            else
                test_pass "Git config is properly templated"
            fi
        fi
    fi
    
    # Configuration directories
    validate_directory "$HOME/.config/nvim" "Neovim config directory"
    
    # Check DOTFILES_DIR is set in shell configs
    if [[ -f "$HOME/.bashrc" ]]; then
        if grep -q "export DOTFILES_DIR=" "$HOME/.bashrc"; then
            test_pass "DOTFILES_DIR set in .bashrc"
        else
            test_fail "DOTFILES_DIR not set in .bashrc" "Re-run installer"
        fi
    fi
    
    if [[ -f "$HOME/.zshrc" ]]; then
        if grep -q "export DOTFILES_DIR=" "$HOME/.zshrc"; then
            test_pass "DOTFILES_DIR set in .zshrc"
        else
            test_fail "DOTFILES_DIR not set in .zshrc" "Re-run installer"
        fi
    fi
}

# Validate shell environment
validate_shell_environment() {
    echo
    test_info "=== VALIDATING SHELL ENVIRONMENT ==="
    
    # Oh My Zsh and plugins
    validate_oh_my_zsh
    
    # NPM global directory setup
    if command_exists npm; then
        local npm_prefix=$(npm config get prefix 2>/dev/null || echo "")
        if [[ "$npm_prefix" == "$HOME/.npm-global" ]]; then
            test_pass "NPM global directory configured correctly"
        else
            test_warn "NPM global directory not set to ~/.npm-global" "Run: npm config set prefix ~/.npm-global"
        fi
    fi
    
    # PATH validations
    if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
        test_pass "~/.local/bin in PATH"
    else
        test_warn "~/.local/bin not in PATH" "Add to shell configuration"
    fi
    
    if command_exists npm; then
        local npm_global_bin="$HOME/.npm-global/bin"
        if [[ ":$PATH:" == *":$npm_global_bin:"* ]]; then
            test_pass "NPM global bin directory in PATH"
        else
            test_warn "NPM global bin not in PATH" "Add $npm_global_bin to PATH"
        fi
    fi
}

# Main validation function
run_validation() {
    echo "🔍 Dotfiles Installation Validation"
    echo "===================================="
    
    # Detect environment
    detect_environment
    
    # Run validations based on category or flags
    case "${CATEGORY:-all}" in
        "base")
            validate_base_packages
            ;;
        "docker")
            validate_docker_comprehensive
            ;;
        "work")
            validate_work_packages
            ;;
        "personal")
            validate_personal_packages
            ;;
        "config")
            validate_configuration_files
            ;;
        "shell")
            validate_shell_environment
            ;;
        "wsl")
            validate_wsl_features
            ;;
        "all")
            validate_base_packages
            validate_docker_comprehensive
            validate_configuration_files
            validate_shell_environment
            
            if [[ "$VALIDATE_WORK" == "true" ]]; then
                validate_work_packages
            fi
            
            if [[ "$VALIDATE_PERSONAL" == "true" ]]; then
                validate_personal_packages
            fi
            
            # WSL validation if applicable
            validate_wsl_features
            ;;
    esac
    
    # Print summary
    print_validation_summary
}

# Main execution
main() {
    # Parse arguments
    parse_arguments "$@"
    
    # Set verbose mode
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        set -x
    fi
    
    # Ensure we're in the right directory
    cd "$DOTFILES_DIR"
    
    # Run validation
    if run_validation; then
        exit 0
    else
        exit 1
    fi
}

# Execute main function
main "$@"