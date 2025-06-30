#!/bin/bash

# Main Dotfiles Installation Script
# Usage: ./install.sh [--work] [--personal] [--force] [--skip-existing] [--recover] [--rollback] [--help]
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

# Load security functions
if [[ -f "$DOTFILES_DIR/scripts/security/core.sh" ]]; then
    source "$DOTFILES_DIR/scripts/security/core.sh"
else
    echo "ERROR: Security functions not found. Exiting for safety."
    exit 1
fi

# Load minimal installation helpers
if [[ -f "$DOTFILES_DIR/scripts/install/state.sh" ]]; then
    source "$DOTFILES_DIR/scripts/install/state.sh"
fi
if [[ -f "$DOTFILES_DIR/scripts/install/error_handler.sh" ]]; then
    source "$DOTFILES_DIR/scripts/install/error_handler.sh"
fi

# Parse command line arguments
INSTALL_WORK=false
INSTALL_PERSONAL=false
FORCE_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --work) INSTALL_WORK=true; shift ;;
        --personal) INSTALL_PERSONAL=true; shift ;;
        --force) FORCE_MODE=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

# Colors and logging
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; PURPLE='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
wsl_log() { echo -e "${PURPLE}[WSL]${NC} $1"; }
work_log() { echo -e "${CYAN}[WORK]${NC} $1"; }
personal_log() { echo -e "${CYAN}[PERSONAL]${NC} $1"; }

# Error handling
handle_error() {
    error "Installation failed at: $1"
    error "Check the error above and try again"
    exit 1
}

# Environment detection
detect_environment() {
    [[ ! "$OSTYPE" == "linux-gnu"* ]] && { error "Linux only. Detected: $OSTYPE"; exit 1; }
    
    if [[ -f /proc/version ]] && grep -q "microsoft\|WSL" /proc/version 2>/dev/null; then
        IS_WSL=true
        WSL_VERSION=$(cat /proc/version | grep -o 'WSL[0-9]' || echo 'WSL1')
        wsl_log "Running in $WSL_VERSION environment"
    else
        IS_WSL=false
        log "Running on native Linux"
    fi
    
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        DISTRO=$ID
        log "Detected: $PRETTY_NAME"
        export DISTRO IS_WSL WSL_VERSION
    else
        error "Could not detect Linux distribution"
        exit 1
    fi
}

# Package management core
get_package_manager() {
    case $DISTRO in
        "ubuntu"|"debian") echo "apt" ;;
        "fedora"|"rhel"|"centos") echo "dnf" ;;  
        "arch"|"manjaro") echo "pacman" ;;
        *) echo "unknown" ;;
    esac
}

update_system() {
    local pm=$(get_package_manager)
    log "Updating package manager..."
    
    case $pm in
        "apt") sudo apt update ;;
        "dnf") sudo dnf update -y ;;
        "pacman") sudo pacman -Syu --noconfirm ;;
        *) warn "Unknown package manager for $DISTRO" ;;
    esac
}

# Unified package installation
install_single_package() {
    local package="$1"
    local pm="${2:-$(get_package_manager)}"
    
    # Validate package name
    if ! validate_package_name "$package"; then
        error "Invalid package name: $package"
        return 1
    fi
    
    case $pm in
        "apt")
            if ! dpkg -l | grep -q "^ii  $package "; then
                safe_sudo apt install -y "$package"
            fi
            ;;
        "dnf")
            sudo dnf install -y "$package"
            ;;
        "pacman")
            sudo pacman -S --noconfirm "$package"
            ;;
        *)
            warn "Cannot install package on $DISTRO"
            return 1
            ;;
    esac
}

install_packages() {
    local -n package_array=$1
    local description="$2"
    local pm=$(get_package_manager)
    
    [[ ${#package_array[@]} -eq 0 ]] && return 0
    
    
    log "Installing $description packages..."
    
    case $pm in
        "apt")
            for pkg in "${package_array[@]}"; do
                if ! dpkg -l | grep -q "^ii  $pkg "; then
                    safe_sudo apt install -y "$pkg" || warn "Failed: $pkg"
                fi
            done
            ;;
        "dnf")
            for pkg in "${package_array[@]}"; do
                safe_sudo dnf install -y "$pkg" || warn "Failed: $pkg"
            done
            ;;
        "pacman")
            for pkg in "${package_array[@]}"; do
                safe_sudo pacman -S --noconfirm "$pkg" || warn "Failed: $pkg"
            done
            ;;
        *)
            warn "Cannot install packages on $DISTRO"
            return 1
            ;;
    esac
}

# Alternative package managers
install_snaps() {
    local -n snap_array=$1
    local description="$2"
    
    [[ ${#snap_array[@]} -eq 0 ]] && return 0
    command -v snap >/dev/null || return 0
    
    log "Installing $description snap packages..."
    for pkg in "${snap_array[@]}"; do
        sudo snap install "$pkg" || warn "Failed snap: $pkg"
    done
}

install_npm_packages() {
    local -n npm_array=$1
    local description="$2"
    
    [[ ${#npm_array[@]} -eq 0 ]] && return 0
    command -v npm >/dev/null || return 0
    
    log "Installing $description npm packages..."
    for pkg in "${npm_array[@]}"; do
        npm install -g "$pkg" || warn "Failed npm: $pkg"
    done
}

install_vscode_extensions() {
    local -n ext_array=$1
    local description="$2"
    
    [[ ${#ext_array[@]} -eq 0 ]] && return 0
    command -v code >/dev/null || return 0
    
    log "Installing $description VS Code extensions..."
    for ext in "${ext_array[@]}"; do
        code --install-extension "$ext" || warn "Failed extension: $ext"
    done
}

# Simple Python package installation
install_python_package() {
    local package="$1"
    log "Installing Python package: $package"
    pip3 install --user "$package" || warn "Failed to install $package"
}

# Package name resolution
resolve_package_name() {
    local mapping="$1"
    local pm="$2"
    
    # Sanitize input
    mapping="$(sanitize_input "$mapping")"
    
    [[ "$mapping" != *":"* ]] && { echo "$mapping"; return; }
    
    IFS=':' read -ra parts <<< "$mapping"
    case $pm in
        "apt") echo "${parts[1]}" ;;
        "dnf") echo "${parts[2]}" ;;
        "pacman") echo "${parts[3]}" ;;
        *) echo "${parts[0]}" ;;
    esac
}

build_package_list() {
    local -n mappings=$1
    local -n output=$2
    local pm="$3"
    
    output=()
    for mapping in "${mappings[@]}"; do
        output+=($(resolve_package_name "$mapping" "$pm"))
    done
}

# File operations
backup_dotfiles() {
    log "Backing up existing dotfiles to $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    
    local files=(".zshrc" ".tmux.conf" ".gitconfig" ".vimrc" ".vim" ".ssh/config" ".profile" ".editorconfig" ".ripgreprc" ".config/bat" ".config/fd")
    for file in "${files[@]}"; do
        if [[ -e "$HOME/$file" ]]; then
            mkdir -p "$BACKUP_DIR/$(dirname "$file")"
            cp -r "$HOME/$file" "$BACKUP_DIR/$file"
            log "Backed up $file"
        fi
    done
}

# Safe symlink creation function
create_safe_symlink() {
    local source="$1"
    local target="$2"
    local config_name="$(basename "$target")"
    
    
    # If target doesn't exist, create symlink
    if [[ ! -e "$target" ]]; then
        ln -s "$source" "$target"
        success "Created symlink for $config_name"
        return 0
    fi
    
    # If it's already our symlink, skip
    if [[ -L "$target" ]] && [[ "$(readlink "$target")" == "$source" ]]; then
        log "$config_name already linked correctly"
        return 0
    fi
    
    
    # Handle force mode
    if [[ "$FORCE_MODE" == true ]]; then
        local backup_name="${target}.pre-dotfiles.$(date +%Y%m%d-%H%M%S)"
        mv "$target" "$backup_name"
        ln -s "$source" "$target"
        warn "Force mode: Backed up to $backup_name and created symlink"
        return 0
    fi
    
    # Interactive mode - file exists but isn't our symlink
    if [[ -L "$target" ]]; then
        warn "$config_name is a symlink to $(readlink "$target")"
    else
        warn "$config_name exists and is not a symlink"
    fi
    
    # Offer choices
    echo "Options for $config_name:"
    echo "  1) Skip (keep existing)"
    echo "  2) Backup and replace"
    echo "  3) View differences"
    read -p "Choice [1-3]: " -n 1 -r choice
    echo
    
    case $choice in
        2)
            local backup_name="${target}.pre-dotfiles.$(date +%Y%m%d-%H%M%S)"
            mv "$target" "$backup_name"
            ln -s "$source" "$target"
            success "Backed up to $backup_name and created symlink"
            ;;
        3)
            if command -v diff &>/dev/null; then
                diff -u "$target" "$source" || true
            else
                echo "=== Current $config_name ==="
                head -20 "$target"
                echo -e "\n=== Dotfiles $config_name ==="
                head -20 "$source"
            fi
            # Recursively call to get choice again
            create_safe_symlink "$source" "$target"
            ;;
        *)
            log "Keeping existing $config_name"
            ;;
    esac
}

create_symlinks() {
    log "Creating symlinks..."
    
    # Core config files with enhanced processing
    local configs=(".zshrc" ".tmux.conf" ".gitconfig" ".vimrc" ".profile" ".editorconfig" ".ripgreprc")
    for config in "${configs[@]}"; do
        if [[ -f "$DOTFILES_DIR/configs/$config" ]]; then
            create_safe_symlink "$DOTFILES_DIR/configs/$config" "$HOME/$config"
        else
            warn "Config file not found: $DOTFILES_DIR/configs/$config"
        fi
    done
    
    # Create .config directory symlinks
    setup_config_directory_links
    
    # VS Code settings
    setup_vscode_config
    
    # Executable scripts
    setup_local_bin
    
    
    success "Symlinks created"
}

setup_config_directory_links() {
    log "Setting up .config directory links..."
    
    # Create .config directory if it doesn't exist
    mkdir -p "$HOME/.config"
    
    # Link bat configuration
    if [[ -d "$DOTFILES_DIR/configs/.config/bat" ]]; then
        mkdir -p "$HOME/.config"
        create_safe_symlink "$DOTFILES_DIR/configs/.config/bat" "$HOME/.config/bat"
    fi
    
    # Link fd configuration  
    if [[ -d "$DOTFILES_DIR/configs/.config/fd" ]]; then
        mkdir -p "$HOME/.config"
        create_safe_symlink "$DOTFILES_DIR/configs/.config/fd" "$HOME/.config/fd"
    fi
    
    # Set ripgrep config environment variable in shell config
    if [[ -f "$DOTFILES_DIR/configs/.ripgreprc" ]]; then
        local ripgrep_export='export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"'
        if ! grep -q "RIPGREP_CONFIG_PATH" "$HOME/.zshrc" 2>/dev/null; then
            echo "" >> "$HOME/.zshrc"
            echo "# Ripgrep configuration" >> "$HOME/.zshrc"
            echo "$ripgrep_export" >> "$HOME/.zshrc"
            log "Added RIPGREP_CONFIG_PATH to .zshrc"
        fi
    fi
}

setup_vscode_config() {
    [[ ! -d "$DOTFILES_DIR/configs/vscode" ]] && return
    
    if [[ "$IS_WSL" == true ]]; then
        # Windows VS Code
        local win_path="/mnt/c/Users/$(whoami)/AppData/Roaming/Code/User"
        [[ -d "/mnt/c/Users/$(whoami)" ]] && {
            mkdir -p "$win_path"
            ln -sf "$DOTFILES_DIR/configs/vscode/settings.json" "$win_path/settings.json"
            wsl_log "Linked VS Code settings (Windows)"
        }
        
        # WSL VS Code
        local wsl_path="$HOME/.config/Code/User"
        mkdir -p "$wsl_path"
        ln -sf "$DOTFILES_DIR/configs/vscode/settings.json" "$wsl_path/settings.json"
        wsl_log "Linked VS Code settings (WSL)"
    else
        # Native Linux
        mkdir -p "$HOME/.config/Code/User"
        ln -sf "$DOTFILES_DIR/configs/vscode/settings.json" "$HOME/.config/Code/User/settings.json"
        log "Linked VS Code settings"
    fi
}

setup_local_bin() {
    mkdir -p "$HOME/.local/bin"
    
    # Link executable scripts
    [[ -d "$DOTFILES_DIR/scripts/bin" ]] && {
        find "$DOTFILES_DIR/scripts/bin" -type f -executable -exec ln -sf {} "$HOME/.local/bin/" \;
        log "Linked executable scripts"
    }
    
    # Ensure PATH includes ~/.local/bin
    grep -q "$HOME/.local/bin" "$HOME/.zshrc" 2>/dev/null || 
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
}

setup_shell_integration() {
    log "Setting up shell integration..."
    
    local integration_marker="# DOTFILES_INTEGRATION_START"
    local integration_end="# DOTFILES_INTEGRATION_END"
    
    # Check if integration already exists
    if grep -q "$integration_marker" "$HOME/.zshrc" 2>/dev/null; then
        log "Dotfiles integration already present in .zshrc"
        return 0
    fi
    
    # Check if .zshrc has custom content
    if [[ -f "$HOME/.zshrc" ]] && [[ -s "$HOME/.zshrc" ]]; then
        # Check if it's our symlink
        if [[ ! -L "$HOME/.zshrc" ]] || [[ "$(readlink "$HOME/.zshrc")" != "$DOTFILES_DIR/configs/.zshrc" ]]; then
            warn "Found existing .zshrc with custom content"
            
            
            # Handle force mode
            if [[ "$FORCE_MODE" == true ]]; then
                echo -e "\n$integration_marker" >> "$HOME/.zshrc"
                echo "# Load dotfiles functions and aliases" >> "$HOME/.zshrc"
                echo "DOTFILES_DIR=\"$DOTFILES_DIR\"" >> "$HOME/.zshrc"
                echo 'if [[ -d "$DOTFILES_DIR" ]]; then' >> "$HOME/.zshrc"
                echo '    for file in "$DOTFILES_DIR"/scripts/functions/*.sh; do' >> "$HOME/.zshrc"
                echo '        [[ -r "$file" ]] && source "$file"' >> "$HOME/.zshrc"
                echo '    done' >> "$HOME/.zshrc"
                echo '    for file in "$DOTFILES_DIR"/scripts/aliases/*.sh; do' >> "$HOME/.zshrc"
                echo '        [[ -r "$file" ]] && source "$file"' >> "$HOME/.zshrc"
                echo '    done' >> "$HOME/.zshrc"
                echo 'fi' >> "$HOME/.zshrc"
                echo "$integration_end" >> "$HOME/.zshrc"
                warn "Force mode: Added dotfiles integration to existing .zshrc"
                return 0
            fi
            
            # Interactive mode
            echo "Options:"
            echo "  1) Append dotfiles integration to existing .zshrc"
            echo "  2) Skip integration (manual setup required)"
            echo "  3) View existing .zshrc"
            read -p "Choice [1-3]: " -n 1 -r zsh_choice
            echo
            
            case $zsh_choice in
                1)
                    # Append integration block
                    echo -e "\n$integration_marker" >> "$HOME/.zshrc"
                    echo "# Load dotfiles functions and aliases" >> "$HOME/.zshrc"
                    echo "DOTFILES_DIR=\"$DOTFILES_DIR\"" >> "$HOME/.zshrc"
                    echo 'if [[ -d "$DOTFILES_DIR" ]]; then' >> "$HOME/.zshrc"
                    echo '    for file in "$DOTFILES_DIR"/scripts/functions/*.sh; do' >> "$HOME/.zshrc"
                    echo '        [[ -r "$file" ]] && source "$file"' >> "$HOME/.zshrc"
                    echo '    done' >> "$HOME/.zshrc"
                    echo '    for file in "$DOTFILES_DIR"/scripts/aliases/*.sh; do' >> "$HOME/.zshrc"
                    echo '        [[ -r "$file" ]] && source "$file"' >> "$HOME/.zshrc"
                    echo '    done' >> "$HOME/.zshrc"
                    echo 'fi' >> "$HOME/.zshrc"
                    echo "$integration_end" >> "$HOME/.zshrc"
                    success "Added dotfiles integration to existing .zshrc"
                    ;;
                3)
                    less "$HOME/.zshrc"
                    # Recursive call
                    setup_shell_integration
                    ;;
                *)
                    warn "Skipping shell integration - manual setup required"
                    echo "To enable dotfiles integration, add this to your .zshrc:"
                    echo "source $DOTFILES_DIR/configs/.zshrc"
                    ;;
            esac
        else
            log ".zshrc is already symlinked to dotfiles"
        fi
    else
        # No existing .zshrc or it's empty - safe to proceed normally
        if ! grep -q "Load dotfiles functions and aliases" "$HOME/.zshrc" 2>/dev/null; then
            echo -e "\n$integration_marker" >> "$HOME/.zshrc"
            echo "# Load dotfiles functions and aliases" >> "$HOME/.zshrc"
            echo "DOTFILES_DIR=\"$DOTFILES_DIR\"" >> "$HOME/.zshrc"
            echo 'if [[ -d "$DOTFILES_DIR" ]]; then' >> "$HOME/.zshrc"
            echo '    for file in "$DOTFILES_DIR"/scripts/functions/*.sh; do' >> "$HOME/.zshrc"
            echo '        [[ -r "$file" ]] && source "$file"' >> "$HOME/.zshrc"
            echo '    done' >> "$HOME/.zshrc"
            echo '    for file in "$DOTFILES_DIR"/scripts/aliases/*.sh; do' >> "$HOME/.zshrc"
            echo '        [[ -r "$file" ]] && source "$file"' >> "$HOME/.zshrc"
            echo '    done' >> "$HOME/.zshrc"
            echo 'fi' >> "$HOME/.zshrc"
            echo "$integration_end" >> "$HOME/.zshrc"
            log "Added dotfiles integration to .zshrc"
        fi
    fi
}

# Component installers
install_shell() {
    log "Setting up shell environment..."
    
    # Oh My Zsh
    [[ ! -d "$HOME/.oh-my-zsh" ]] && {
        log "Installing Oh My Zsh..."
        local temp_dir=$(mktemp -d -m 700)
        local install_script="$temp_dir/install.sh"
        
        # Download and verify Oh My Zsh installer
        local oh_my_zsh_url="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
        local oh_my_zsh_checksum="b1c3baa891427ed3e592e8c69a693fb3f20ac039a09203de3e0c0ef7ba059c3e"
        
        # Download and verify installer script
        if ! verify_download "$oh_my_zsh_url" \
                           "$oh_my_zsh_checksum" \
                           "$install_script" \
                           "Oh My Zsh installer"; then
            error "Failed to download or verify Oh My Zsh installer"
            rm -rf "$temp_dir"
            return 1
        fi
        
        # Basic validation - check it's a shell script and contains expected content
        if [[ -f "$install_script" ]] && \
           head -1 "$install_script" | grep -q "^#!/" && \
           grep -q "Oh My Zsh" "$install_script"; then
            log "Oh My Zsh installer validated"
            chmod +x "$install_script"
            RUNZSH=no CHSH=no sh "$install_script" --unattended
        else
            error "Oh My Zsh installer validation failed"
            rm -rf "$temp_dir"
            return 1
        fi
        
        rm -rf "$temp_dir"
    }
    
    # Plugins and theme
    local custom_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    local plugins=(
        "zsh-autosuggestions:https://github.com/zsh-users/zsh-autosuggestions"
        "zsh-syntax-highlighting:https://github.com/zsh-users/zsh-syntax-highlighting"
        "zsh-completions:https://github.com/zsh-users/zsh-completions"
    )
    
    for plugin in "${plugins[@]}"; do
        IFS=':' read -ra parts <<< "$plugin"
        local name="${parts[0]}" url="${parts[1]}"
        [[ ! -d "$custom_dir/plugins/$name" ]] && 
            git clone "$url" "$custom_dir/plugins/$name"
    done
    
    # Powerlevel10k theme
    [[ ! -d "$custom_dir/themes/powerlevel10k" ]] && 
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$custom_dir/themes/powerlevel10k"
    
    # Set default shell
    [[ "$SHELL" != "$(which zsh)" ]] && {
        log "Setting zsh as default shell..."
        chsh -s "$(which zsh)"
        warn "Log out and back in for shell change to take effect"
    }
    
    success "Shell setup complete"
}

install_fonts() {
    log "Setting up fonts..."
    mkdir -p "$HOME/.local/share/fonts"
    
    if ! fc-list | grep -q "Cascadia Code PL"; then
        log "Installing Cascadia Code PL..."
        local temp_dir=$(mktemp -d -m 700)
        local font_archive="$temp_dir/cascadia.zip"
        
        # Cascadia Code v2111.01 download with verification
        local font_url="https://github.com/microsoft/cascadia-code/releases/download/v2111.01/CascadiaCode-2111.01.zip"
        local expected_hash="51fd68176dffb87e2fbc79381aef7f5c9488b58918dee223cd7439b5aa14e712"
        
        if verify_download "$font_url" "$expected_hash" "$font_archive" "Cascadia Code font"; then
            (
                cd "$temp_dir"
                unzip -q cascadia.zip &&
                cp ttf/CascadiaCodePL*.ttf "$HOME/.local/share/fonts/" &&
                fc-cache -f -v &&
                success "Cascadia Code PL installed"
            ) || warn "Failed to extract and install Cascadia Code font"
        else
            warn "Failed to download or verify Cascadia Code font"
        fi
        
        rm -rf "$temp_dir"
    fi
}

# Import Windows SSH files with validation
import_windows_ssh_files() {
    local win_ssh_dir="$1"
    local import_all="${2:-false}"
    
    # SSH key files to consider
    local ssh_files=(id_rsa id_rsa.pub id_ed25519 id_ed25519.pub id_ecdsa id_ecdsa.pub known_hosts config)
    
    for file in "${ssh_files[@]}"; do
        local win_file="$win_ssh_dir/$file"
        local local_file="$HOME/.ssh/$file"
        
        # Skip if Windows file doesn't exist
        [[ ! -e "$win_file" ]] && continue
        
        # Skip if local file exists and we're not importing all
        if [[ "$import_all" == false && -e "$local_file" ]]; then
            continue
        fi
        
        # Handle different file types
        case "$file" in
            id_*|*.pub)
                # SSH key files - validate before copying
                if [[ "$file" =~ \.pub$ ]]; then
                    # Public keys - basic validation
                    if [[ -f "$win_file" ]] && grep -qE "^(ssh-rsa|ssh-ed25519|ecdsa-sha2)" "$win_file"; then
                        if secure_copy_ssh_key "$win_file" "$local_file" true; then
                            wsl_log "Imported SSH public key: $file"
                        else
                            warn "Failed to import SSH public key: $file"
                        fi
                    else
                        warn "Invalid SSH public key format: $file"
                    fi
                elif validate_ssh_key "$win_file"; then
                    # Private keys - full validation
                    if secure_copy_ssh_key "$win_file" "$local_file" true; then
                        wsl_log "Imported SSH private key: $file"
                    else
                        warn "Failed to import SSH private key: $file"
                    fi
                else
                    warn "Invalid SSH key, skipping: $file"
                fi
                ;;
            known_hosts)
                # Known hosts file - basic validation
                if [[ -f "$win_file" ]] && [[ -s "$win_file" ]]; then
                    # Use install for atomic permission setting
                    install -m 644 "$win_file" "$local_file"
                    wsl_log "Imported known_hosts"
                else
                    warn "Invalid or empty known_hosts file"
                fi
                ;;
            config)
                # SSH config file - basic validation
                if [[ -f "$win_file" ]] && [[ -s "$win_file" ]]; then
                    # Basic validation - check it looks like SSH config
                    if head -10 "$win_file" | grep -q -E "^(Host|HostName|User|Port|IdentityFile)" || [[ ! -s "$win_file" ]]; then
                        # Use install for atomic permission setting
                        install -m 644 "$win_file" "$local_file"
                        wsl_log "Imported SSH config"
                    else
                        warn "SSH config file appears invalid, skipping"
                    fi
                else
                    warn "Invalid or empty SSH config file"
                fi
                ;;
        esac
    done
}

setup_ssh() {
    log "Setting up SSH..."
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    
    if [[ "$IS_WSL" == true ]]; then
        local win_ssh="/mnt/c/Users/$(whoami)/.ssh"
        if [[ -d "$win_ssh" ]]; then
            wsl_log "Found Windows SSH directory"
            
            # Check for existing SSH files
            local ssh_files=(id_* known_hosts config)
            local existing_files=()
            
            for pattern in "${ssh_files[@]}"; do
                for file in "$HOME/.ssh"/$pattern; do
                    if [[ -e "$file" ]]; then
                        existing_files+=("$(basename "$file")")
                    fi
                done
            done
            
            # Remove duplicates from array
            existing_files=($(printf "%s\n" "${existing_files[@]}" | sort -u))
            
            if [[ ${#existing_files[@]} -gt 0 ]]; then
                warn "Found existing SSH files: ${existing_files[*]}"
                
                
                # Handle force mode
                if [[ "$FORCE_MODE" == true ]]; then
                    local ssh_backup="$HOME/.ssh.backup.$(date +%Y%m%d-%H%M%S)"
                    cp -r "$HOME/.ssh" "$ssh_backup"
                    wsl_log "Force mode: Backed up SSH to $ssh_backup"
                    cp "$win_ssh"/{id_*,known_hosts,config} "$HOME/.ssh/" 2>/dev/null
                else
                    # Interactive mode
                    echo "Options:"
                    echo "  1) Skip SSH import (keep existing)"
                    echo "  2) Backup and import Windows SSH"
                    echo "  3) Merge (import only missing files)"
                    read -p "Choice [1-3]: " -n 1 -r ssh_choice
                    echo
                    
                    case $ssh_choice in
                        2)
                            # Backup existing SSH
                            local ssh_backup="$HOME/.ssh.backup.$(date +%Y%m%d-%H%M%S)"
                            cp -r "$HOME/.ssh" "$ssh_backup"
                            wsl_log "Backed up SSH to $ssh_backup"
                            # Import all with validation
                            import_windows_ssh_files "$win_ssh" true
                            ;;
                        3)
                            # Import only missing files with validation
                            import_windows_ssh_files "$win_ssh" false
                            ;;
                        *)
                            wsl_log "Skipping SSH import"
                            return 0
                            ;;
                    esac
                fi
            else
                # No existing files, safe to import with validation
                import_windows_ssh_files "$win_ssh" true
            fi
            
            # Fix permissions
            chmod 600 "$HOME/.ssh"/id_* 2>/dev/null
            chmod 644 "$HOME/.ssh"/*.pub 2>/dev/null
            chmod 644 "$HOME/.ssh"/{known_hosts,config} 2>/dev/null
            
            wsl_log "SSH setup complete"
            ls "$HOME/.ssh"/id_*.pub 2>/dev/null && wsl_log "Available keys:" && ls -la "$HOME/.ssh"/id_*.pub
        else
            wsl_log "No Windows SSH directory found"
        fi
    else
        log "SSH directory ready. Create keys with: ssh-keygen -t ed25519"
    fi
}

setup_wsl() {
    [[ "$IS_WSL" != true ]] && return
    
    wsl_log "Configuring WSL integration..."
    
    # Source core WSL functions
    if [[ -f "$DOTFILES_DIR/scripts/wsl/core.sh" ]]; then
        source "$DOTFILES_DIR/scripts/wsl/core.sh"
        
        # Setup WSL environment
        setup_wsl_environment
        
        # Setup clipboard integration
        setup_wsl_clipboard
        
        wsl_log "WSL integration complete"
    else
        warn "WSL core functions not found"
    fi
}

setup_docker() {
    command -v docker >/dev/null && {
        log "Adding user to docker group..."
        sudo usermod -aG docker "$USER"
        log "Docker configured. Log out/in for group change to take effect"
    }
}

# Pre-installation report
show_installation_plan() {
    echo "=== Installation Plan ==="
    echo
    echo "Mode: Base$([ "$INSTALL_WORK" == true ] && echo " + Work")$([ "$INSTALL_PERSONAL" == true ] && echo " + Personal")"
    echo
    echo "Configuration files to create/modify:"
    
    # Check configs
    local configs=(".zshrc" ".tmux.conf" ".gitconfig" ".vimrc")
    for config in "${configs[@]}"; do
        if [[ -e "$HOME/$config" ]]; then
            if [[ -L "$HOME/$config" ]]; then
                echo "  $config - exists (symlink to $(readlink "$HOME/$config"))"
            else
                echo "  $config - EXISTS (regular file) ⚠️"
            fi
        else
            echo "  $config - will create"
        fi
    done
    
    # Check SSH
    if [[ "$IS_WSL" == true ]] && [[ -d "$HOME/.ssh" ]]; then
        local ssh_files=$(ls -1 "$HOME/.ssh" 2>/dev/null | wc -l)
        if [[ $ssh_files -gt 0 ]]; then
            echo "  .ssh/ - EXISTS with $ssh_files files ⚠️"
        fi
    fi
    
    # Check for existing installations
    echo
    echo "Existing installations:"
    command -v zsh &>/dev/null && echo "  ✓ zsh installed"
    [[ -d "$HOME/.oh-my-zsh" ]] && echo "  ✓ Oh My Zsh installed"
    command -v docker &>/dev/null && echo "  ✓ Docker installed"
    command -v code &>/dev/null && [[ "$INSTALL_WORK" == true ]] && echo "  ✓ VS Code installed"
    
    echo
    if [[ "$FORCE_MODE" == true ]]; then
        warn "Force mode enabled - will overwrite existing files with backups"
    elif [[ "$SKIP_MODE" == true ]]; then
        log "Skip mode enabled - will preserve all existing files"
    else
        log "Interactive mode - will ask before overwriting"
    fi
    
    echo
    read -p "Continue with installation? [Y/n]: " -r
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Installation cancelled"
        exit 0
    fi
}

# Main orchestration
run_setup() {
    local setup_type="$1"
    local setup_file="$DOTFILES_DIR/setup/${setup_type}_setup.sh"
    
    [[ ! -f "$setup_file" ]] && { warn "$setup_type setup file not found"; return 1; }
    
    log "Running $setup_type setup..."
    source "$setup_file" || handle_error "$setup_type setup"
    success "$setup_type setup complete"
}

show_help() {
    cat << EOF
Linux Dotfiles Installation Script

Usage: $0 [options]

Options:
  --work           Install work-specific tools (Azure CLI, VS Code)
  --personal       Install personal tools (currently just ffmpeg)
  --force          Force installation, overwrite existing files
  -h, --help       Show this help

Examples:
  $0                    # Base installation only (interactive)
  $0 --work            # Base + work tools  
  $0 --personal        # Base + personal tools
  $0 --work --personal # Everything
  $0 --force           # Overwrite existing configs (with backups)

This script provides a modern development environment with:
- Zsh shell with Oh My Zsh and plugins
- Modern CLI tools (eza, bat, fzf, ripgrep)
- Docker and development essentials
- VS Code and extensions (with --work)
- WSL integration (auto-detected)
EOF
}

print_next_steps() {
    success "Installation complete!"
    echo
    log "Next steps:"
    echo "1. Restart terminal or run: source ~/.zshrc"
    echo "2. Configure Powerlevel10k: p10k configure"
    
    if [[ "$IS_WSL" == true ]]; then
        echo "3. WSL commands available: win-ssh, use-key, sync-windows-ssh"
    else
        echo "3. Create SSH keys: ssh-keygen -t ed25519"
    fi
    
    [[ "$SHELL" != "$(which zsh)" ]] && echo "4. Log out/in for shell change"
    [[ "$INSTALL_WORK" == true ]] && work_log "Work tools installed"
    [[ "$INSTALL_PERSONAL" == true ]] && personal_log "Personal tools installed"
}

# Main execution
main() {
    log "Starting dotfiles installation..."
    
    detect_environment || handle_error "environment detection"
    
    # Show installation plan unless in force mode
    if [[ "$FORCE_MODE" != true ]]; then
        show_installation_plan
    fi
    
    backup_dotfiles || handle_error "backup"
    update_system || handle_error "system update"
    
    # Run setup scripts
    run_setup "base"
    [[ "$INSTALL_WORK" == true ]] && run_setup "work"
    [[ "$INSTALL_PERSONAL" == true ]] && run_setup "personal"
    
    # System configuration
    create_symlinks || handle_error "symlinks"
    install_shell || handle_error "shell setup"
    setup_shell_integration || handle_error "shell integration"
    install_fonts || handle_error "font installation"
    setup_ssh || handle_error "SSH setup"
    setup_wsl || handle_error "WSL setup"
    setup_docker || handle_error "Docker setup"
    
    print_next_steps
}

main "$@"
