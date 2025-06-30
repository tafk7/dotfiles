#!/bin/bash

# Work setup script - Professional development tools
# This file is sourced by install.sh when --work flag is used

# Enable strict error handling
set -e
set -u
set -o pipefail

# Error trap for cleanup
trap 'handle_error "work_setup.sh at line $LINENO"' ERR

work_log "Configuring work environment..."

# Install Azure CLI
install_azure_cli() {
    work_log "Installing Azure CLI..."
    
    case $DISTRO in
        "ubuntu"|"debian")
            # Secure Azure CLI installation for Debian/Ubuntu
            work_log "Adding Microsoft repository securely..."
            
            # Install prerequisites
            safe_sudo apt-get update
            safe_sudo apt-get install -y ca-certificates curl apt-transport-https lsb-release gnupg
            
            # Download and verify Microsoft signing key
            local temp_dir=$(mktemp -d -m 700)
            local ms_key="$temp_dir/microsoft.asc"
            local ms_key_url="https://packages.microsoft.com/keys/microsoft.asc"
            local ms_key_checksum="bc528686b5086ded5e1d5453f0768ee85e0126bafc0ed167a470a4fbc91fd3f1"
            
            if verify_download "$ms_key_url" "$ms_key_checksum" "$ms_key" "Microsoft GPG key"; then
                # Import the key
                safe_sudo apt-key add "$ms_key"
                
                # Add repository
                local repo_entry="deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main"
                echo "$repo_entry" | safe_sudo tee /etc/apt/sources.list.d/azure-cli.list
                
                # Update and install
                safe_sudo apt-get update
                safe_sudo apt-get install -y azure-cli
            else
                error "Failed to download Microsoft signing key"
                rm -rf "$temp_dir"
                return 1
            fi
            
            rm -rf "$temp_dir"
            ;;
        "fedora"|"rhel"|"centos")
            # Import Microsoft key and install via dnf
            work_log "Installing via Microsoft repository..."
            safe_sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            safe_sudo dnf install -y azure-cli
            ;;
        "arch"|"manjaro")
            if command -v yay &> /dev/null; then
                yay -S --noconfirm azure-cli
            else
                warn "Azure CLI requires AUR helper (yay) on Arch"
                work_log "Install with: yay -S azure-cli"
                return 1
            fi
            ;;
        *)
            warn "Azure CLI installation not configured for $DISTRO"
            work_log "Manual install: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
            return 1
            ;;
    esac
    
    if command -v az &> /dev/null; then
        success "Azure CLI installed"
        work_log "Login with: az login"
    else
        warn "Azure CLI installation may have failed"
        return 1
    fi
}

# Install VS Code
install_vscode() {
    work_log "Installing VS Code..."
    
    case $DISTRO in
        "ubuntu"|"debian")
            # Secure VS Code installation for Debian/Ubuntu
            work_log "Adding Microsoft repository securely for VS Code..."
            
            # Install prerequisites if not already present
            safe_sudo apt-get update
            safe_sudo apt-get install -y ca-certificates curl apt-transport-https gnupg
            
            # Download and add Microsoft signing key
            local temp_dir=$(mktemp -d -m 700)
            local ms_key="$temp_dir/microsoft.asc"
            local ms_key_url="https://packages.microsoft.com/keys/microsoft.asc"
            local ms_key_checksum="bc528686b5086ded5e1d5453f0768ee85e0126bafc0ed167a470a4fbc91fd3f1"
            
            if verify_download "$ms_key_url" "$ms_key_checksum" "$ms_key" "Microsoft GPG key"; then
                # Import the key
                safe_sudo apt-key add "$ms_key"
                
                # Add repository
                local repo_entry="deb [arch=amd64,arm64,armhf] https://packages.microsoft.com/repos/code stable main"
                echo "$repo_entry" | safe_sudo tee /etc/apt/sources.list.d/vscode.list
                
                # Update and install
                safe_sudo apt-get update
                safe_sudo apt-get install -y code
            else
                error "Failed to download Microsoft signing key for VS Code"
                rm -rf "$temp_dir"
                return 1
            fi
            
            rm -rf "$temp_dir"
            ;;
        "fedora"|"rhel"|"centos")
            # Import Microsoft key and install via dnf
            work_log "Installing VS Code via Microsoft repository..."
            safe_sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            
            # Create repository file securely
            local repo_content="[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc"
            
            echo "$repo_content" | safe_sudo tee /etc/yum.repos.d/vscode.repo
            safe_sudo dnf check-update
            safe_sudo dnf install -y code
            ;;
        "arch"|"manjaro")
            if command -v yay &> /dev/null; then
                yay -S --noconfirm visual-studio-code-bin
            else
                warn "VS Code requires AUR helper (yay) on Arch"
                work_log "Install with: yay -S visual-studio-code-bin"
                return 1
            fi
            ;;
        *)
            # Fallback to snap
            if command -v snap &> /dev/null; then
                work_log "Using snap as fallback..."
                safe_sudo snap install code --classic
            else
                warn "VS Code installation not configured for $DISTRO"
                work_log "Manual install: https://code.visualstudio.com/docs/setup/linux"
                return 1
            fi
            ;;
    esac
    
    if command -v code &> /dev/null; then
        success "VS Code installed"
    else
        warn "VS Code installation may have failed"
        return 1
    fi
}

# Run installations
install_azure_cli || warn "Azure CLI installation failed"
install_vscode || warn "VS Code installation failed"

# Install work npm packages
declare -a work_npm_packages=("yarn" "typescript" "eslint" "prettier" "nodemon")
install_npm_packages work_npm_packages "work"

# Install Python development tools
if command -v pip3 &> /dev/null; then
    work_log "Installing Python development tools..."
    
    # Source install.sh functions if not already available
    if ! command -v install_python_package &> /dev/null; then
        source "$DOTFILES_DIR/install.sh"
    fi
    
    local python_packages=("black" "flake8" "mypy" "pylint")
    for pkg in "${python_packages[@]}"; do
        install_python_package "$pkg"
    done
    
    success "Python tools configured"
else
    warn "pip3 not found - skipping Python tools installation"
fi

# Install work VS Code extensions
declare -a work_vscode_extensions=(
    "ms-vscode-remote.remote-wsl"
    "ms-python.python"
    "esbenp.prettier-vscode"
    "ms-azuretools.vscode-docker"
)
install_vscode_extensions work_vscode_extensions "work"

success "Work environment configured"
