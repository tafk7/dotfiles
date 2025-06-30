#!/bin/bash

# Microsoft Integration Functions
# Consolidated Microsoft GPG key handling and repository setup

# Source required functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../security/core.sh"  # For verify_download
# safe_sudo is available from common.sh (loaded by install.sh)

# Microsoft GPG key details
declare -g MS_KEY_URL="https://packages.microsoft.com/keys/microsoft.asc"
declare -g MS_KEY_CHECKSUM="bc528686b5086ded5e1d5453f0768ee85e0126bafc0ed167a470a4fbc91fd3f1"

# Download and verify Microsoft GPG key
setup_microsoft_key() {
    local temp_dir=$(mktemp -d -m 700)
    local ms_key="$temp_dir/microsoft.asc"
    
    if verify_download "$MS_KEY_URL" "$MS_KEY_CHECKSUM" "$ms_key" "Microsoft GPG key"; then
        echo "$ms_key"  # Return path to verified key
        return 0
    else
        rm -rf "$temp_dir"
        return 1
    fi
}

# Setup Microsoft repository for apt-based systems
setup_microsoft_apt_repo() {
    local tool_name="$1"
    local repo_path="$2"
    
    work_log "Adding Microsoft repository for $tool_name..."
    
    # Install prerequisites
    safe_sudo apt-get update
    safe_sudo apt-get install -y ca-certificates curl apt-transport-https lsb-release gnupg
    
    # Get verified Microsoft key
    local ms_key
    if ms_key=$(setup_microsoft_key); then
        # Import the key (modern method)
        gpg --dearmor < "$ms_key" | safe_sudo tee /usr/share/keyrings/microsoft-archive-keyring.gpg > /dev/null
        
        # Add repository with signed-by
        local repo_entry="deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/$repo_path/ $(lsb_release -cs) main"
        echo "$repo_entry" | safe_sudo tee "/etc/apt/sources.list.d/$tool_name.list"
        
        # Update package lists
        safe_sudo apt-get update
        
        # Clean up
        rm -rf "$(dirname "$ms_key")"
        return 0
    else
        error "Failed to download Microsoft signing key for $tool_name"
        return 1
    fi
}

# Setup Microsoft repository for dnf-based systems
setup_microsoft_dnf_repo() {
    local tool_name="$1"
    local repo_url="$2"
    
    work_log "Adding Microsoft repository for $tool_name..."
    
    # Get verified Microsoft key
    local ms_key
    if ms_key=$(setup_microsoft_key); then
        # Import the key
        safe_sudo rpm --import "$ms_key"
        
        # Create repository file if provided
        if [[ -n "$repo_url" ]]; then
            local repo_content="[code]
name=Visual Studio Code
baseurl=$repo_url
enabled=1
gpgcheck=1
gpgkey=$MS_KEY_URL"
            
            echo "$repo_content" | safe_sudo tee "/etc/yum.repos.d/$tool_name.repo"
            safe_sudo dnf check-update
        fi
        
        # Clean up
        rm -rf "$(dirname "$ms_key")"
        return 0
    else
        error "Failed to download Microsoft signing key for $tool_name"
        return 1
    fi
}

# Install Azure CLI using Microsoft repository
install_azure_cli_microsoft() {
    work_log "Installing Azure CLI via Microsoft repository..."
    
    case $PACKAGE_MANAGER in
        "apt")
            if setup_microsoft_apt_repo "azure-cli" "azure-cli"; then
                safe_sudo apt-get install -y azure-cli
                return 0
            fi
            ;;
        "dnf")
            if setup_microsoft_dnf_repo "azure-cli" ""; then
                safe_sudo dnf install -y azure-cli
                return 0
            fi
            ;;
        "pacman")
            if command -v yay &> /dev/null; then
                yay -S --noconfirm azure-cli
                return 0
            else
                warn "Azure CLI requires AUR helper (yay) on Arch"
                work_log "Install with: yay -S azure-cli"
                return 1
            fi
            ;;
        *)
            warn "Azure CLI installation not configured for $PACKAGE_MANAGER"
            work_log "Manual install: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
            return 1
            ;;
    esac
    
    return 1
}

# Install VS Code using Microsoft repository
install_vscode_microsoft() {
    work_log "Installing VS Code via Microsoft repository..."
    
    case $PACKAGE_MANAGER in
        "apt")
            # VS Code has different architecture requirements
            if setup_microsoft_apt_repo "vscode" "code"; then
                # Fix the repository entry for VS Code with modern signed-by
                local repo_entry="deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/code stable main"
                echo "$repo_entry" | safe_sudo tee /etc/apt/sources.list.d/vscode.list
                safe_sudo apt-get update
                safe_sudo apt-get install -y code
                return 0
            fi
            ;;
        "dnf")
            if setup_microsoft_dnf_repo "vscode" "https://packages.microsoft.com/yumrepos/vscode"; then
                safe_sudo dnf install -y code
                return 0
            fi
            ;;
        "pacman")
            if command -v yay &> /dev/null; then
                yay -S --noconfirm visual-studio-code-bin
                return 0
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
                return 0
            else
                warn "VS Code installation not configured for $PACKAGE_MANAGER"
                work_log "Manual install: https://code.visualstudio.com/docs/setup/linux"
                return 1
            fi
            ;;
    esac
    
    return 1
}

# Export functions for use by other scripts
export -f setup_microsoft_key setup_microsoft_apt_repo setup_microsoft_dnf_repo
export -f install_azure_cli_microsoft install_vscode_microsoft