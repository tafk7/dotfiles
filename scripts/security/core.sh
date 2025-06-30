#!/bin/bash
# Core Security Functions for Dotfiles Installation
# Streamlined to include only actually used functions

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
    
    # Download with security settings
    if ! curl --tlsv1.2 --fail --silent --show-error --location \
         --max-time 300 --retry 3 --retry-delay 2 \
         --user-agent "dotfiles-installer/1.0" \
         "$url" -o "$output_file"; then
        error "Download failed: $url"
        return 1
    fi
    
    # Verify checksum
    local actual_hash=$(sha256sum "$output_file" | cut -d' ' -f1)
    if [[ "$actual_hash" != "$expected_hash" ]]; then
        error "Checksum verification failed for $description"
        error "Expected: $expected_hash"
        error "Actual:   $actual_hash"
        rm -f "$output_file"
        return 1
    fi
    
    success "Verified $description (SHA256: ${expected_hash:0:16}...)"
    return 0
}



