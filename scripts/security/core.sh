#!/bin/bash

# Core Security Functions for Dotfiles Installation
# This file provides essential security utilities for safe installation

# Verify downloaded files with SHA256 checksums
verify_download() {
    local url="$1"
    local expected_hash="$2"
    local output_file="$3"
    local description="${4:-download}"
    
    # Validate inputs
    [[ -z "$url" || -z "$expected_hash" || -z "$output_file" ]] && {
        error "verify_download: Missing required parameters"
        return 1
    }
    
    # Ensure HTTPS only
    [[ "$url" =~ ^https:// ]] || {
        error "Only HTTPS URLs allowed: $url"
        return 1
    }
    
    log "Downloading $description..."
    log "URL: $url"
    log "Expected SHA256: $expected_hash"
    
    # Download with security settings
    if ! curl --tlsv1.2 --fail --silent --show-error --location \
             --connect-timeout 30 --max-time 300 \
             --user-agent "dotfiles-installer/1.0" \
             "$url" -o "$output_file"; then
        error "Download failed: $url"
        rm -f "$output_file"
        return 1
    fi
    
    # Verify file was downloaded
    [[ -f "$output_file" ]] || {
        error "Download completed but file not found: $output_file"
        return 1
    }
    
    # Verify checksum
    log "Verifying checksum..."
    local actual_hash
    actual_hash=$(sha256sum "$output_file" | cut -d' ' -f1)
    
    if [[ "$actual_hash" != "$expected_hash" ]]; then
        error "Checksum verification failed for $description"
        error "Expected: $expected_hash"
        error "Actual:   $actual_hash"
        rm -f "$output_file"
        return 1
    fi
    
    success "Download verified: $description"
    return 0
}

# Sanitize user input to prevent injection attacks
sanitize_input() {
    local input="$1"
    local type="${2:-general}"
    
    [[ -z "$input" ]] && {
        error "sanitize_input: Empty input"
        return 1
    }
    
    case "$type" in
        "package")
            # Allow package names: letters, numbers, dots, hyphens, underscores
            if [[ "$input" =~ ^[a-zA-Z0-9._-]+$ ]] && [[ ${#input} -le 100 ]]; then
                echo "$input"
            else
                error "Invalid package name: $input"
                return 1
            fi
            ;;
        "path")
            # Basic path validation - no null bytes, control characters
            if [[ "$input" =~ ^[[:print:]]+$ ]] && [[ ! "$input" =~ [\|\&\;\`] ]]; then
                echo "$input"
            else
                error "Invalid path: $input"
                return 1
            fi
            ;;
        "version")
            # Version strings: numbers, dots, dashes
            if [[ "$input" =~ ^[0-9a-zA-Z.-]+$ ]] && [[ ${#input} -le 50 ]]; then
                echo "$input"
            else
                error "Invalid version: $input"
                return 1
            fi
            ;;
        "general"|*)
            # General safe input: alphanumeric plus basic punctuation
            if [[ "$input" =~ ^[a-zA-Z0-9._/ -]+$ ]] && [[ ${#input} -le 200 ]]; then
                echo "$input"
            else
                error "Invalid input: $input"
                return 1
            fi
            ;;
    esac
}

# Validate package names before installation
validate_package_name() {
    local package="$1"
    local pm="${2:-$(get_package_manager)}"
    
    # Sanitize package name
    package=$(sanitize_input "$package" "package") || return 1
    
    # Additional package manager specific validation
    case "$pm" in
        "apt")
            # Check if package exists in repositories
            if ! apt-cache show "$package" >/dev/null 2>&1; then
                warn "Package not found in repositories: $package"
                return 1
            fi
            ;;
        "dnf")
            # Check if package exists
            if ! dnf info "$package" >/dev/null 2>&1; then
                warn "Package not found in repositories: $package"
                return 1
            fi
            ;;
        "pacman")
            # Check if package exists
            if ! pacman -Si "$package" >/dev/null 2>&1; then
                warn "Package not found in repositories: $package"
                return 1
            fi
            ;;
    esac
    
    echo "$package"
}

# Secure path construction to prevent path traversal
safe_path_construction() {
    local base_path="$1"
    local relative_path="$2"
    
    # Sanitize inputs
    base_path=$(sanitize_input "$base_path" "path") || return 1
    relative_path=$(sanitize_input "$relative_path" "path") || return 1
    
    # Prevent path traversal
    if [[ "$relative_path" =~ \.\./|\.\.\\ ]]; then
        error "Path traversal detected: $relative_path"
        return 1
    fi
    
    # Construct safe path
    local full_path="$base_path/$relative_path"
    
    # Normalize path
    full_path=$(realpath -m "$full_path") || {
        error "Invalid path construction: $base_path + $relative_path"
        return 1
    }
    
    # Ensure the path is within the base directory
    if [[ ! "$full_path" =~ ^"$(realpath -m "$base_path")" ]]; then
        error "Path outside base directory: $full_path"
        return 1
    fi
    
    echo "$full_path"
}

# Secure network operation with validation
secure_network_operation() {
    local url="$1"
    local description="${2:-network operation}"
    
    # Validate URL
    [[ -z "$url" ]] && {
        error "No URL provided"
        return 1
    }
    
    # Ensure HTTPS only
    [[ "$url" =~ ^https:// ]] || {
        error "Only HTTPS URLs allowed: $url"
        return 1
    }
    
    log "Validating network connectivity for $description..."
    
    # Check if we can reach the host
    if ! curl --tlsv1.2 --fail --silent --head \
             --connect-timeout 10 --max-time 30 \
             "$url" >/dev/null; then
        error "Cannot reach URL: $url"
        return 1
    fi
    
    success "Network validation successful for $description"
    return 0
}

# Verify GPG signatures for package repositories
verify_gpg_signature() {
    local file="$1"
    local signature_file="$2"
    local keyring="${3:-}"
    
    [[ -f "$file" && -f "$signature_file" ]] || {
        error "Missing file or signature: $file, $signature_file"
        return 1
    }
    
    log "Verifying GPG signature..."
    
    local gpg_cmd="gpg --verify"
    [[ -n "$keyring" ]] && gpg_cmd="$gpg_cmd --keyring $keyring"
    
    if $gpg_cmd "$signature_file" "$file" >/dev/null 2>&1; then
        success "GPG signature verification successful"
        return 0
    else
        error "GPG signature verification failed"
        return 1
    fi
}

# Safe sudo execution with confirmation
safe_sudo() {
    local operation="$*"
    
    [[ -z "$operation" ]] && {
        error "No sudo operation specified"
        return 1
    }
    
    # In force mode, skip confirmation but log the operation
    if [[ "$FORCE_MODE" == true ]]; then
        warn "Force mode: Executing sudo operation: $operation"
        sudo "$@"
        return $?
    fi
    
    # In skip mode, don't execute sudo operations
    if [[ "$SKIP_MODE" == true ]]; then
        warn "Skip mode: Skipping sudo operation: $operation"
        return 0
    fi
    
    # Interactive confirmation
    warn "About to execute with administrator privileges:"
    warn "Command: $operation"
    read -p "Continue? [y/N]: " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "User confirmed sudo operation"
        sudo "$@"
        return $?
    else
        warn "User cancelled sudo operation"
        return 1
    fi
}

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

# Network retry logic for unreliable connections
retry_network_operation() {
    local max_attempts="${1:-3}"
    local delay="${2:-5}"
    shift 2
    local operation="$*"
    
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        log "Network operation attempt $attempt/$max_attempts"
        
        if eval "$operation"; then
            success "Network operation successful on attempt $attempt"
            return 0
        else
            if [[ $attempt -lt $max_attempts ]]; then
                warn "Attempt $attempt failed, retrying in ${delay}s..."
                sleep "$delay"
                # Exponential backoff
                delay=$((delay * 2))
            else
                error "Network operation failed after $max_attempts attempts"
                return 1
            fi
        fi
        
        ((attempt++))
    done
}