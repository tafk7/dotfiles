#!/bin/bash
# Configuration validation system for dotfiles installation




# Check symlink integrity
check_symlink_integrity() {
    local link="$1"
    local target="$2"
    
    if [[ -L "$link" ]]; then
        local actual_target=$(readlink "$link")
        if [[ "$actual_target" == "$target" ]]; then
            log "Symlink OK: $(basename "$link")"
            return 0
        else
            warn "Symlink mismatch: $(basename "$link")"
            warn "  Expected: $target"
            warn "  Actual: $actual_target"
            return 1
        fi
    else
        if [[ -e "$link" ]]; then
            warn "Not a symlink: $link"
            return 1
        else
            log "Symlink missing: $(basename "$link") (will be created)"
            return 0
        fi
    fi
}

# Validate essential configuration files only
validate_essential_configs() {
    log "Validating essential configurations..."
    
    # Check critical symlinks only
    local critical_links=(
        "$HOME/.gitconfig:$DOTFILES_DIR/configs/.gitconfig"
        "$HOME/.profile:$DOTFILES_DIR/configs/.profile"
    )
    
    local validation_passed=true
    for link_spec in "${critical_links[@]}"; do
        IFS=':' read -r link target <<< "$link_spec"
        check_symlink_integrity "$link" "$target" || validation_passed=false
    done
    
    if [[ "$validation_passed" == true ]]; then
        success "Essential validations passed"
        return 0
    else
        warn "Some symlink validations failed"
        return 1
    fi
}

# Pre-installation validation
pre_install_validation() {
    log "Running pre-installation validation..."
    
    # Check for required commands
    local required_commands=("git" "curl" "bash")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        error "Missing required commands: ${missing_commands[*]}"
        return 1
    fi
    
    # Check bash version (need 4.0+)
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        error "Bash 4.0+ required (current: ${BASH_VERSION})"
        return 1
    fi
    
    # Check disk space (need at least 100MB)
    local available_space=$(df -BM "$HOME" | awk 'NR==2 {print $4}' | sed 's/M//')
    if [[ "$available_space" -lt 100 ]]; then
        error "Insufficient disk space (need 100MB, have ${available_space}MB)"
        return 1
    fi
    
    success "Pre-installation validation passed"
    return 0
}

# Post-installation validation (essential checks only)
post_install_validation() {
    log "Running post-installation validation..."
    
    # Validate essential configs only
    validate_essential_configs
    
    # Check if critical commands are available
    local critical_commands=("git" "curl")
    local missing=()
    
    for cmd in "${critical_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Critical commands missing: ${missing[*]}"
        return 1
    fi
    
    success "Post-installation validation complete"
}