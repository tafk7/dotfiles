#!/bin/bash

# Work setup script - Professional development tools
# This file is sourced by install.sh when --work flag is used

work_log "Configuring work environment..."

# Install Azure CLI
install_azure_cli() {
    work_log "Installing Azure CLI..."
    
    case $DISTRO in
        "ubuntu"|"debian")
            curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
            ;;
        "fedora"|"rhel"|"centos")
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            sudo dnf install -y azure-cli
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
            curl -sSL https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
            echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list
            sudo apt update
            sudo apt install -y code
            ;;
        "fedora"|"rhel"|"centos")
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
            sudo dnf check-update
            sudo dnf install -y code
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
                sudo snap install code --classic
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
