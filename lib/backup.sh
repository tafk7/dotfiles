#!/bin/bash
# Backup functions for dotfiles installation
# Simple, pragmatic backup management

# Prevent double-sourcing
[[ -n "${DOTFILES_BACKUP_LOADED:-}" ]] && return 0
readonly DOTFILES_BACKUP_LOADED=1

# Backup directory within the repository
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../" && pwd)}"
readonly DOTFILES_BACKUP_PREFIX="$DOTFILES_DIR/.backups"

# Create backup directory with timestamp
create_backup_dir() {
    # Ensure .backups directory exists
    mkdir -p "$DOTFILES_BACKUP_PREFIX"
    
    local backup_dir="$DOTFILES_BACKUP_PREFIX/backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    echo "$backup_dir"
}

# Backup a single file
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        # Ensure .backups directory exists
        mkdir -p "$DOTFILES_BACKUP_PREFIX"
        
        local filename=$(basename "$file")
        local backup="$DOTFILES_BACKUP_PREFIX/${filename}.backup-$(date +%Y%m%d-%H%M%S)"
        cp "$file" "$backup"
        log "Backed up: $file -> $backup"
    fi
}

# Create symlink with backup
safe_symlink() {
    local source="$1"
    local target="$2"
    local backup_dir="$3"
    
    # Check if source exists
    if [[ ! -e "$source" ]]; then
        error "Source file does not exist: $source"
        return 1
    fi
    
    # Skip backup if force overwrite is enabled
    if [[ "${FORCE_OVERWRITE:-false}" == "true" && -e "$target" ]]; then
        log "Force overwrite enabled, removing $target"
        rm -rf "$target"
    elif [[ -e "$target" && ! -L "$target" ]]; then
        # If target exists and is not a symlink, back it up
        log "Backing up existing $target"
        mv "$target" "$backup_dir/$(basename "$target")"
    elif [[ -L "$target" ]]; then
        # Remove existing symlink
        rm "$target"
    fi
    
    # Create the symlink
    ln -s "$source" "$target"
    success "Linked $source -> $target"
}

# Cleanup old backups (keep most recent N backups)
cleanup_old_backups() {
    local keep_count="${1:-10}"  # Default to keeping 10 backups
    local backup_type="${2:-}"   # Optional backup type filter
    
    if [[ ! -d "$DOTFILES_BACKUP_PREFIX" ]]; then
        return 0
    fi
    
    log "Cleaning up old backups (keeping last $keep_count)..."
    
    # If backup type specified, filter by it
    if [[ -n "$backup_type" ]]; then
        # List directories matching the type pattern
        ls -dt "$DOTFILES_BACKUP_PREFIX"/*"$backup_type"* 2>/dev/null | tail -n +$((keep_count + 1)) | xargs rm -rf 2>/dev/null || true
    else
        # Clean all backup directories
        ls -dt "$DOTFILES_BACKUP_PREFIX"/* 2>/dev/null | tail -n +$((keep_count + 1)) | xargs rm -rf 2>/dev/null || true
    fi
}

# Export functions
export -f create_backup_dir backup_file safe_symlink cleanup_old_backups