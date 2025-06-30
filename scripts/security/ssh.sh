#!/bin/bash

# Consolidated SSH Key Management
# Combines SSH validation, copying, and WSL import functionality

# Source common utilities if not already loaded
if ! declare -f is_wsl >/dev/null 2>&1; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../core/common.sh"
fi

# WSL logging function if not already defined
if ! declare -f wsl_log >/dev/null 2>&1; then
    wsl_log() {
        echo -e "\033[35m[WSL]\033[0m $*"
    }
fi

# Validate SSH key files
validate_ssh_key() {
    local key_file="$1"
    local key_type="${2:-}"
    
    [[ -f "$key_file" ]] || {
        error "SSH key file not found: $key_file"
        return 1
    }
    
    # Check if it's a valid SSH key
    if ssh-keygen -l -f "$key_file" >/dev/null 2>&1; then
        log "Valid SSH key: $key_file"
        
        # Optional: Check key type if specified
        if [[ -n "$key_type" ]]; then
            local actual_type
            actual_type=$(ssh-keygen -l -f "$key_file" | awk '{print $4}' | tr -d '()')
            if [[ "$actual_type" != "$key_type" ]]; then
                warn "SSH key type mismatch. Expected: $key_type, Found: $actual_type"
            fi
        fi
        
        return 0
    else
        error "Invalid SSH key: $key_file"
        return 1
    fi
}

# Secure SSH key copying with individual validation
secure_copy_ssh_key() {
    local src="$1"
    local dest="$2"
    local backup_existing="${3:-true}"
    
    [[ -f "$src" ]] || {
        error "Source SSH key not found: $src"
        return 1
    }
    
    # Validate source key
    validate_ssh_key "$src" || {
        error "Source key validation failed: $src"
        return 1
    }
    
    # Backup existing key if requested
    if [[ "$backup_existing" == true && -f "$dest" ]]; then
        local backup_name="${dest}.backup.$(date +%Y%m%d-%H%M%S)"
        cp "$dest" "$backup_name"
        log "Backed up existing key to: $backup_name"
    fi
    
    # Copy and set permissions
    cp "$src" "$dest" || {
        error "Failed to copy SSH key: $src -> $dest"
        return 1
    }
    
    # Set appropriate permissions
    if [[ "$dest" =~ \.pub$ ]]; then
        chmod 644 "$dest"
    else
        chmod 600 "$dest"
    fi
    
    success "SSH key copied securely: $(basename "$dest")"
    return 0
}

# WSL SSH import functionality (consolidated from wsl/core.sh)
import_windows_ssh_keys() {
    # Only run in WSL
    if ! is_wsl; then
        return 0
    fi
    
    local win_user=$(get_windows_username)
    local win_ssh_dir="/mnt/c/Users/$win_user/.ssh"
    
    if [[ ! -d "$win_ssh_dir" ]]; then
        wsl_log "Windows SSH directory not found: $win_ssh_dir"
        return 1
    fi
    
    wsl_log "Importing SSH keys from Windows..."
    
    # Create Linux SSH directory
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    
    # Import SSH keys with validation
    local imported_count=0
    for key_file in "$win_ssh_dir"/id_*; do
        [[ ! -f "$key_file" ]] && continue
        
        local filename=$(basename "$key_file")
        local dest="$HOME/.ssh/$filename"
        
        # Skip if already exists
        if [[ -f "$dest" ]]; then
            log "Skipping $filename (already exists)"
            continue
        fi
        
        # Copy with appropriate permissions and validation
        if [[ "$filename" =~ \.pub$ ]]; then
            # Public key - basic validation
            if grep -qE "^(ssh-rsa|ssh-ed25519|ecdsa-sha2)" "$key_file" 2>/dev/null; then
                install -m 644 "$key_file" "$dest"
                wsl_log "Imported public key: $filename"
                ((imported_count++))
            else
                warn "Skipping invalid public key format: $filename"
            fi
        else
            # Private key - full validation
            if validate_ssh_key "$key_file"; then
                install -m 600 "$key_file" "$dest"
                wsl_log "Imported private key: $filename"
                ((imported_count++))
            else
                warn "Skipping invalid private key: $filename"
            fi
        fi
    done
    
    # Import known_hosts if exists
    if [[ -f "$win_ssh_dir/known_hosts" ]]; then
        install -m 644 "$win_ssh_dir/known_hosts" "$HOME/.ssh/known_hosts"
        wsl_log "Imported known_hosts"
        ((imported_count++))
    fi
    
    # Import SSH config if exists
    if [[ -f "$win_ssh_dir/config" ]]; then
        # Basic validation - check it looks like SSH config
        if head -10 "$win_ssh_dir/config" | grep -q -E "^(Host|HostName|User|Port|IdentityFile)" || [[ ! -s "$win_ssh_dir/config" ]]; then
            install -m 644 "$win_ssh_dir/config" "$HOME/.ssh/config"
            wsl_log "Imported SSH config"
            ((imported_count++))
        else
            warn "SSH config file appears invalid, skipping"
        fi
    fi
    
    if [[ $imported_count -gt 0 ]]; then
        success "Imported $imported_count SSH items from Windows"
    else
        log "No SSH items to import from Windows"
    fi
    
    return 0
}

# Enhanced SSH setup with Windows integration
setup_ssh_with_wsl_integration() {
    log "Setting up SSH configuration..."
    
    # Create SSH directory
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    
    # If in WSL, try to import from Windows
    if is_wsl; then
        import_windows_ssh_keys
    fi
    
    # Set proper permissions on all SSH files
    if [[ -d "$HOME/.ssh" ]]; then
        # Fix permissions on private keys
        find "$HOME/.ssh" -name 'id_*' -not -name '*.pub' -exec chmod 600 {} \; 2>/dev/null
        
        # Fix permissions on public keys
        find "$HOME/.ssh" -name '*.pub' -exec chmod 644 {} \; 2>/dev/null
        
        # Fix permissions on known_hosts and config
        [[ -f "$HOME/.ssh/known_hosts" ]] && chmod 644 "$HOME/.ssh/known_hosts"
        [[ -f "$HOME/.ssh/config" ]] && chmod 644 "$HOME/.ssh/config"
        
        success "SSH permissions configured"
    fi
    
    # Show available keys
    if ls "$HOME/.ssh"/id_*.pub >/dev/null 2>&1; then
        log "Available SSH keys:"
        ls -la "$HOME/.ssh"/id_*.pub
    else
        log "No SSH keys found. Generate with: ssh-keygen -t ed25519"
    fi
}

# List available SSH keys with details
list_ssh_keys() {
    if [[ ! -d "$HOME/.ssh" ]]; then
        warn "SSH directory not found"
        return 1
    fi
    
    echo "SSH Keys:"
    local found_keys=false
    
    for key_file in "$HOME/.ssh"/id_*.pub; do
        if [[ -f "$key_file" ]]; then
            found_keys=true
            local key_info
            key_info=$(ssh-keygen -l -f "$key_file" 2>/dev/null)
            echo "  $(basename "$key_file"): $key_info"
        fi
    done
    
    if [[ "$found_keys" == false ]]; then
        echo "  No SSH keys found"
        echo "  Generate with: ssh-keygen -t ed25519 -C 'your_email@example.com'"
    fi
}

# Export functions for use by other scripts
export -f validate_ssh_key secure_copy_ssh_key import_windows_ssh_keys
export -f setup_ssh_with_wsl_integration list_ssh_keys