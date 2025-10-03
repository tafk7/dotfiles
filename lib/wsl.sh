#!/bin/bash
# WSL-specific functions for dotfiles
# Handles Windows Subsystem for Linux integration

# Prevent double-sourcing
[[ -n "${DOTFILES_WSL_LOADED:-}" ]] && return 0
readonly DOTFILES_WSL_LOADED=1

# Check if running on WSL
is_wsl() {
    [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]] || [[ -n "${WSL_DISTRO_NAME:-}" ]]
}

# Get Windows username for WSL operations
get_windows_username() {
    if is_wsl; then
        # Use cmd.exe to get Windows username - simple and reliable
        local win_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' | tr -d ' ')
        
        # Validate it's not empty or a system account
        if [[ -z "$win_user" ]] || [[ "$win_user" == "SYSTEM" ]] || [[ "$win_user" == "Administrator" ]]; then
            # Fallback to current user
            win_user="$USER"
        fi
        
        echo "$win_user"
    fi
}

# Setup WSL clipboard integration  
setup_wsl_clipboard() {
    if ! is_wsl; then
        return 0
    fi
    
    wsl_log "Setting up WSL clipboard integration..."
    
    local bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir"
    
    # Create pbcopy script
    cat > "$bin_dir/pbcopy" << 'EOF'
#!/bin/bash
clip.exe
EOF
    
    # Create pbpaste script  
    cat > "$bin_dir/pbpaste" << 'EOF'
#!/bin/bash
powershell.exe -command "Get-Clipboard" | sed 's/\r$//'
EOF
    
    chmod +x "$bin_dir/pbcopy" "$bin_dir/pbpaste"
    
    # Ensure ~/.local/bin is in PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        export PATH="$HOME/.local/bin:$PATH"
    fi
    
    success "WSL clipboard integration setup complete"
}

# Import SSH keys from Windows (WSL only)
import_windows_ssh_keys() {
    if ! is_wsl; then
        return 0
    fi
    
    local win_user=$(get_windows_username)
    if [[ -z "$win_user" ]]; then
        warn "Could not determine Windows username for SSH key import"
        return 1
    fi
    
    local windows_ssh_dir="/mnt/c/Users/$win_user/.ssh"
    
    if [[ ! -d "$windows_ssh_dir" ]]; then
        wsl_log "No Windows SSH directory found at $windows_ssh_dir"
        return 0
    fi
    
    wsl_log "Importing SSH keys from Windows..."
    
    local ssh_dir="$HOME/.ssh"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    
    # Copy SSH keys with proper permissions
    for key_file in "$windows_ssh_dir"/*; do
        if [[ -f "$key_file" ]]; then
            local filename=$(basename "$key_file")
            local target="$ssh_dir/$filename"
            
            cp "$key_file" "$target"
            
            # Set appropriate permissions
            if [[ "$filename" == *.pub ]]; then
                chmod 644 "$target"
            else
                chmod 600 "$target"
            fi
            
            wsl_log "Imported SSH key: $filename"
        fi
    done
    
    success "SSH key import completed"
}

# Export functions
export -f is_wsl get_windows_username