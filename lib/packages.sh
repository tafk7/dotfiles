#!/bin/bash
# Package management for simplified dotfiles installation
# Ubuntu-only support with essential packages

# Source core functions
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/core.sh"

# Check if packages are available in repositories
check_package_availability() {
    local packages=("$@")
    local available_packages=()
    local missing_packages=()
    
    for pkg in "${packages[@]}"; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            available_packages+=("$pkg")
        else
            missing_packages+=("$pkg")
            warn "Package not available in repositories: $pkg"
        fi
    done
    
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        warn "Missing packages: ${missing_packages[*]}"
    fi
    
    # Return available packages via global array
    AVAILABLE_PACKAGES=("${available_packages[@]}")
    return 0
}

# Unified package installation function with verification
install_packages() {
    local packages=("$@")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        warn "No packages to install"
        return 0
    fi
    
    # Check package availability first
    check_package_availability "${packages[@]}"
    
    if [[ ${#AVAILABLE_PACKAGES[@]} -eq 0 ]]; then
        warn "No packages available for installation"
        return 1  # Return failure so fallback methods can be triggered
    fi
    
    log "Installing packages: ${AVAILABLE_PACKAGES[*]}"
    
    if safe_sudo apt-get install -y "${AVAILABLE_PACKAGES[@]}"; then
        success "Package installation completed"
        return 0
    else
        error "Package installation failed"
        return 1
    fi
}

# Install base packages - essential tools for everyone
install_base_packages() {
    log "Installing base packages..."
    
    # Update package lists first
    safe_sudo apt-get update
    
    # Essential packages for Ubuntu
    local base_packages=(
        # Build tools
        "build-essential"
        "curl" 
        "wget"
        "git"
        "unzip"
        "zip"
        "jq"
        
        # Repository management
        "software-properties-common"
        
        # Shell and modern CLI tools
        "zsh"
        # neovim installed separately with PPA for latest version
        "bat" 
        "fd-find"
        "ripgrep"
        "fzf"
        
        # Development essentials
        "python3-pip"
        "pipx"
        
        # System utilities
        "openssh-client"
    )
    
    install_packages "${base_packages[@]}"
    
    # Install packages that may need alternative installation methods
    install_modern_cli_tools
    
    # Install Node.js (handle separately due to npm conflicts)
    install_nodejs
    
    # Install Docker (requires special handling)
    install_docker
    
    # WSL-specific packages
    if [[ "$IS_WSL" == "true" ]]; then
        install_wsl_packages
    fi
    
    success "Base packages installation completed"
}

# Install modern CLI tools with fallback methods for Ubuntu 24.04+
install_modern_cli_tools() {
    log "Installing modern CLI tools with fallbacks..."
    
    # Install neovim from PPA for latest stable version
    install_neovim_latest
    
    # Try to install eza via package manager first, fallback to GitHub release
    if ! command_exists eza; then
        if ! install_packages "eza"; then
            log "eza not available in repos, installing from GitHub..."
            install_eza_from_github
        fi
    fi
    
    # Install glow for markdown viewing
    if ! command_exists glow; then
        log "Installing glow for markdown viewing..."
        # Try apt first (might be available in some repos)
        if ! install_packages "glow"; then
            # Fallback to snap
            log "glow not in apt repos, trying snap..."
            if command_exists snap; then
                execute_with_feedback "sudo snap install glow" "Installing glow via snap"
            else
                log_error "Neither apt nor snap available for glow installation"
                log "You can install glow manually later with: sudo snap install glow"
            fi
        fi
    fi
}

# Install latest stable neovim using AppImage
install_neovim_latest() {
    log "Installing latest stable Neovim..."
    
    # Check if neovim is already installed
    if command_exists nvim; then
        local current_version=$(nvim --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        log "Current Neovim version: $current_version"
        
        # Ask user if they want to update
        if [[ -t 0 ]]; then
            read -p "Neovim is already installed. Update to latest? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                success "Keeping existing Neovim installation"
                return 0
            fi
        fi
    fi
    
    # Install using AppImage for consistent latest version
    log "Downloading latest Neovim AppImage..."
    local nvim_url="https://github.com/neovim/neovim/releases/latest/download/nvim.appimage"
    local temp_file="/tmp/nvim.appimage"
    
    if curl -fsSL "$nvim_url" -o "$temp_file"; then
        # Make executable and move to /usr/local/bin
        chmod +x "$temp_file"
        
        # Remove old nvim if it exists
        if [[ -f /usr/local/bin/nvim ]]; then
            safe_sudo rm -f /usr/local/bin/nvim
        fi
        
        # Install the AppImage
        safe_sudo mv "$temp_file" /usr/local/bin/nvim
        
        # Verify installation
        if command_exists nvim; then
            local new_version=$(nvim --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
            success "Neovim $new_version installed successfully via AppImage"
            
            # Install python support for neovim
            log "Installing Python support for Neovim..."
            if command_exists pip3; then
                pip3 install --user pynvim || warn "Failed to install pynvim"
            fi
        else
            error "Failed to install Neovim AppImage"
            return 1
        fi
    else
        error "Failed to download Neovim AppImage"
        warn "Falling back to package manager installation..."
        
        # Try PPA as fallback
        if safe_sudo add-apt-repository -y ppa:neovim-ppa/unstable; then
            safe_sudo apt-get update
            install_packages "neovim"
        else
            # Final fallback to distribution package
            install_packages "neovim"
        fi
    fi
}

# Install eza from GitHub releases
install_eza_from_github() {
    log "Installing eza from GitHub releases..."
    
    local eza_version="v0.18.2"  # Latest stable as of Ubuntu 24.04
    local eza_url="https://github.com/eza-community/eza/releases/download/${eza_version}/eza_x86_64-unknown-linux-gnu.tar.gz"
    local temp_dir=$(mktemp -d)
    
    if curl -fsSL "$eza_url" -o "$temp_dir/eza.tar.gz"; then
        cd "$temp_dir"
        tar -xzf eza.tar.gz
        if [[ -f "eza" ]]; then
            safe_sudo mv eza /usr/local/bin/eza
            safe_sudo chmod +x /usr/local/bin/eza
            success "eza installed from GitHub"
        else
            warn "Failed to extract eza binary"
        fi
        cd - >/dev/null
        rm -rf "$temp_dir"
    else
        warn "Failed to download eza from GitHub"
    fi
}


# Install Docker with Ubuntu-specific setup
install_docker() {
    log "Installing Docker..."
    
    # Add Docker's official GPG key and repository
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor | safe_sudo tee /usr/share/keyrings/docker-archive-keyring.gpg > /dev/null
    
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        safe_sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    safe_sudo apt-get update
    log "Installing Docker..."
    install_packages "docker-ce"
    log "Installing Docker Compose V2..."
    install_packages "docker-compose-plugin"
    
    # Add user to docker group with improved error handling
    if groups | grep -q docker; then
        log "User already in docker group"
        # Verify Docker is actually working
        if docker version >/dev/null 2>&1; then
            success "Docker is working correctly"
        else
            warn "Docker group membership exists but Docker is not responding"
        fi
    else
        log "Adding user to docker group..."
        if safe_sudo usermod -aG docker "$USER"; then
            success "Added user to docker group"
            
            # Provide clear instructions for group activation
            echo
            log "Docker group activation options:"
            log "  1. Restart your shell: exec \$SHELL"
            log "  2. Or run: newgrp docker"
            log "  3. Or log out and back in"
            echo
            
            # Test if newgrp is available and try it non-interactively
            if command_exists newgrp; then
                log "Testing docker group activation..."
                # Use a non-interactive test to avoid hanging the script
                if timeout 5 newgrp docker sh -c 'docker version >/dev/null 2>&1' 2>/dev/null; then
                    success "Docker group activated successfully"
                else
                    warn "Auto-activation failed. Please restart your shell or run 'newgrp docker'"
                fi
            else
                warn "newgrp command not available. Please restart your shell to use Docker"
            fi
        else
            error "Failed to add user to docker group"
            return 1
        fi
    fi
}

# Install Node.js and npm
install_nodejs() {
    log "Installing Node.js and npm..."
    
    # First, check if nodejs is already installed
    if command_exists node; then
        log "Node.js is already installed: $(node --version)"
        if command_exists npm; then
            log "npm is already installed: $(npm --version)"
            return 0
        fi
    fi
    
    # Try to install nodejs with npm included
    # On Ubuntu 24.04, nodejs package should include npm
    if safe_sudo apt-get install -y nodejs; then
        # Check if npm came with nodejs
        if command_exists npm; then
            success "Node.js and npm installed successfully"
            return 0
        else
            # If npm isn't included, try to install it separately
            log "npm not included with nodejs, attempting separate installation..."
            if safe_sudo apt-get install -y npm; then
                success "npm installed successfully"
                return 0
            else
                warn "Failed to install npm package, trying NodeSource repository..."
            fi
        fi
    fi
    
    # Fallback: Use NodeSource repository for latest Node.js
    log "Installing Node.js from NodeSource repository..."
    
    # Install dependencies
    safe_sudo apt-get install -y ca-certificates curl gnupg
    
    # Add NodeSource GPG key
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | safe_sudo gpg --dearmor -o /usr/share/keyrings/nodesource.gpg
    
    # Add NodeSource repository (Node.js 20.x LTS)
    NODE_MAJOR=20
    echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | safe_sudo tee /etc/apt/sources.list.d/nodesource.list
    
    # Update and install
    safe_sudo apt-get update
    if safe_sudo apt-get install -y nodejs; then
        success "Node.js and npm installed from NodeSource"
        return 0
    else
        error "Failed to install Node.js"
        return 1
    fi
}

# Install WSL-specific packages
install_wsl_packages() {
    wsl_log "Installing WSL-specific packages..."
    
    # Ensure universe repository is enabled for wslu
    log "Ensuring universe repository is enabled..."
    if ! safe_sudo add-apt-repository -y universe; then
        warn "Failed to add universe repository"
    fi
    
    # Update package lists after adding repository
    safe_sudo apt-get update
    
    local wsl_packages=(
        "socat"
        "wslu"
    )
    
    install_packages "${wsl_packages[@]}"
}

# Install work packages - professional development tools
install_work_packages() {
    log "Installing work packages..."
    
    # Install Azure CLI (Ubuntu-specific)
    install_azure_cli_ubuntu
    
    # Install Node.js development tools
    install_nodejs_tools
    
    # Install Python development tools  
    install_python_tools
    
    success "Work environment configured"
}

# Install Azure CLI for Ubuntu (simplified from complex cross-platform version)
install_azure_cli_ubuntu() {
    log "Installing Azure CLI for Ubuntu..."
    
    # Download and verify Microsoft GPG key
    local ms_key_url="https://packages.microsoft.com/keys/microsoft.asc"
    local temp_key=$(mktemp)
    
    if curl -fsSL "$ms_key_url" -o "$temp_key"; then
        # Import the key
        cat "$temp_key" | gpg --dearmor | \
            safe_sudo tee /usr/share/keyrings/microsoft-archive-keyring.gpg > /dev/null
        rm "$temp_key"
        
        # Add repository
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] \
            https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" | \
            safe_sudo tee /etc/apt/sources.list.d/azure-cli.list > /dev/null
        
        # Update and install
        safe_sudo apt-get update
        log "Installing Azure CLI..."
        install_packages "azure-cli"
        
        success "Azure CLI installed - login with: az login"
    else
        error "Failed to download Microsoft GPG key"
        return 1
    fi
}

# Helper function to install a list of development tools with consistent logging
install_tool_packages() {
    local tool_type="$1"
    local installer="$2"
    shift 2
    
    for pkg in "$@"; do
        log "Installing $tool_type package: $pkg"
        if $installer "$pkg"; then
            success "$pkg installed"
        else
            warn "Failed to install $pkg"
        fi
    done
}

# Install Node.js development tools
install_nodejs_tools() {
    if ! command_exists npm; then
        warn "npm not found - skipping Node.js tools installation"
        return 1
    fi
    
    log "Installing Node.js development tools..."
    
    # Setup npm global directory first
    setup_npm_global
    
    # Use the helper function for consistent installation
    install_tool_packages "Node.js" "npm install -g" yarn eslint prettier
}

# Install Python development tools
install_python_tools() {
    if ! command_exists pip3; then
        warn "pip3 not found - skipping Python tools installation"
        return 1
    fi
    
    log "Installing Python development tools..."
    
    # Ensure pipx PATH is set up if pipx is available
    if command_exists pipx; then
        log "Ensuring pipx PATH configuration..."
        pipx ensurepath >/dev/null 2>&1 || warn "Could not configure pipx PATH automatically"
    fi
    
    # Modern Python tools - ruff replaces flake8, mypy, pylint
    local python_packages=("black" "ruff")
    for pkg in "${python_packages[@]}"; do
        log "Installing Python package: $pkg"
        
        # Try pipx first (isolated environments), then pip3 --user as fallback
        if command_exists pipx; then
            if pipx install "$pkg"; then
                success "$pkg installed via pipx" 
                continue
            fi
        fi
        
        if pip3 install --user "$pkg"; then
            success "$pkg installed via pip"
        else
            warn "Failed to install $pkg"
        fi
    done
}

# Install personal packages - media and entertainment tools  
install_personal_packages() {
    log "Installing personal packages..."
    
    local personal_packages=(
        "ffmpeg"
        "yt-dlp"
    )
    
    install_packages "${personal_packages[@]}"
    
    success "Personal environment configured"
}

# Setup Zsh environment with Oh My Zsh and plugins
setup_zsh_environment() {
    log "Setting up Zsh environment..."
    
    # Install Oh My Zsh (non-interactively)
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        log "Installing Oh My Zsh..."
        # Use --unattended flag to skip interactive prompts
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || {
            warn "Oh My Zsh installation failed, continuing..."
        }
    else
        log "Oh My Zsh already installed"
    fi
    
    # Install Powerlevel10k theme
    local p10k_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [[ ! -d "$p10k_dir" ]]; then
        log "Installing Powerlevel10k theme..."
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir" || {
            warn "Powerlevel10k installation failed, continuing..."
        }
    else
        log "Powerlevel10k already installed"
    fi
    
    # Install additional plugins
    local custom_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    
    # zsh-autosuggestions
    if [[ ! -d "$custom_dir/plugins/zsh-autosuggestions" ]]; then
        log "Installing zsh-autosuggestions plugin..."
        git clone https://github.com/zsh-users/zsh-autosuggestions "$custom_dir/plugins/zsh-autosuggestions" || {
            warn "zsh-autosuggestions installation failed"
        }
    fi
    
    # zsh-syntax-highlighting
    if [[ ! -d "$custom_dir/plugins/zsh-syntax-highlighting" ]]; then
        log "Installing zsh-syntax-highlighting plugin..."
        git clone https://github.com/zsh-users/zsh-syntax-highlighting "$custom_dir/plugins/zsh-syntax-highlighting" || {
            warn "zsh-syntax-highlighting installation failed"
        }
    fi
    
    # zsh-completions
    if [[ ! -d "$custom_dir/plugins/zsh-completions" ]]; then
        log "Installing zsh-completions plugin..."
        git clone https://github.com/zsh-users/zsh-completions "$custom_dir/plugins/zsh-completions" || {
            warn "zsh-completions installation failed"
        }
    fi
    
    # Setup FZF shell integration
    setup_fzf_integration
    
    success "Zsh environment setup completed"
}

# Setup FZF shell integration for Ubuntu 24.04+
setup_fzf_integration() {
    log "Setting up FZF shell integration..."
    
    # FZF installed via apt doesn't create shell integration files
    # We need to create them manually or source from system locations
    
    if command_exists fzf; then
        # Ubuntu package locations for FZF integration
        local fzf_bash_completion="/usr/share/bash-completion/completions/fzf"
        local fzf_bash_keybindings="/usr/share/doc/fzf/examples/key-bindings.bash"
        local fzf_zsh_completion="/usr/share/zsh/vendor-completions/_fzf"
        local fzf_zsh_keybindings="/usr/share/doc/fzf/examples/key-bindings.zsh"
        
        # Create ~/.fzf.bash if system files exist
        if [[ -f "$fzf_bash_keybindings" ]]; then
            log "Creating FZF bash integration..."
            {
                echo "# FZF bash integration - auto-generated by dotfiles installer"
                echo "source '$fzf_bash_keybindings'"
                [[ -f "$fzf_bash_completion" ]] && echo "source '$fzf_bash_completion'"
            } > "$HOME/.fzf.bash"
            success "FZF bash integration created"
        fi
        
        # Create ~/.fzf.zsh if system files exist
        if [[ -f "$fzf_zsh_keybindings" ]]; then
            log "Creating FZF zsh integration..."
            {
                echo "# FZF zsh integration - auto-generated by dotfiles installer"
                echo "source '$fzf_zsh_keybindings'"
                [[ -f "$fzf_zsh_completion" ]] && echo "source '$fzf_zsh_completion'"
            } > "$HOME/.fzf.zsh"
            success "FZF zsh integration created"
        fi
        
        # If system files don't exist, install FZF properly via git
        if [[ ! -f "$fzf_bash_keybindings" ]] && [[ ! -f "$fzf_zsh_keybindings" ]]; then
            log "System FZF integration files not found, installing via git..."
            install_fzf_from_git
        fi
    else
        warn "FZF not found, skipping shell integration"
    fi
}

# Install FZF from git with proper shell integration
install_fzf_from_git() {
    log "Installing FZF from git with shell integration..."
    
    local fzf_dir="$HOME/.fzf"
    
    if [[ ! -d "$fzf_dir" ]]; then
        if git clone --depth 1 https://github.com/junegunn/fzf.git "$fzf_dir"; then
            log "Running FZF installation script..."
            # Run the install script with auto-accept for bash/zsh integration
            if "$fzf_dir/install" --bash --zsh --no-update-rc; then
                success "FZF installed with shell integration"
            else
                warn "FZF installation script failed"
            fi
        else
            warn "Failed to clone FZF repository"
        fi
    else
        log "FZF git installation already exists"
    fi
}