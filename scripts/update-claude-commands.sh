#!/bin/bash
# Update Claude slash commands by syncing from dotfiles to ~/.claude/commands

# Source the core library for logging functions
DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export DOTFILES_DIR
source "$DOTFILES_DIR/lib/core.sh"

# Define paths
DOTFILES_COMMANDS="$DOTFILES_DIR/ai/commands"
CLAUDE_COMMANDS="$HOME/.claude/commands"
DOTFILES_CLAUDE_MD="$DOTFILES_DIR/ai/global-CLAUDE.md"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
BACKUP_DIR="$DOTFILES_BACKUP_PREFIX/claude_commands_$(date +%Y%m%d_%H%M%S)"

# Check if source directory exists
if [[ ! -d "$DOTFILES_COMMANDS" ]]; then
    log_error "Source directory not found: $DOTFILES_COMMANDS"
    exit 1
fi

# Main update function
update_claude_commands() {
    log_info "Updating Claude slash commands..."
    
    # Create ~/.claude directory if it doesn't exist
    if [[ ! -d "$HOME/.claude" ]]; then
        log_info "Creating ~/.claude directory..."
        mkdir -p "$HOME/.claude"
    fi
    
    # Backup existing commands if they exist
    if [[ -d "$CLAUDE_COMMANDS" ]]; then
        # Ensure backup directory exists
        mkdir -p "$DOTFILES_BACKUP_PREFIX"
        
        log_info "Backing up existing commands to: $BACKUP_DIR"
        cp -r "$CLAUDE_COMMANDS" "$BACKUP_DIR"
        
        # Remove existing commands
        log_info "Removing existing commands directory..."
        rm -rf "$CLAUDE_COMMANDS"
    fi
    
    # Copy new commands
    log_info "Copying commands from dotfiles..."
    cp -r "$DOTFILES_COMMANDS" "$CLAUDE_COMMANDS"
    
    # Verify the copy
    if [[ -d "$CLAUDE_COMMANDS" ]]; then
        local count=$(find "$CLAUDE_COMMANDS" -name "*.md" -type f | wc -l)
        log_success "Successfully installed $count command files"
        
        # Show the command structure
        echo ""
        log_info "Command structure:"
        tree -d "$CLAUDE_COMMANDS" 2>/dev/null || find "$CLAUDE_COMMANDS" -type d | sort | sed 's|'"$CLAUDE_COMMANDS"'/||' | sed 's|^|  |'
    else
        log_error "Failed to copy commands"
        
        # Attempt to restore backup
        if [[ -d "$BACKUP_DIR" ]]; then
            log_info "Attempting to restore from backup..."
            mv "$BACKUP_DIR" "$CLAUDE_COMMANDS"
        fi
        exit 1
    fi
    
    # Cleanup old backups (keep last 5)
    cleanup_old_backups 5 "claude_commands"
    
    echo ""
    log_success "Claude commands updated successfully!"
    log_info "Previous commands backed up to: $BACKUP_DIR"
}

# Update CLAUDE.md function
update_claude_md() {
    log_info "Updating CLAUDE.md..."
    
    # Check if source file exists
    if [[ ! -f "$DOTFILES_CLAUDE_MD" ]]; then
        log_error "Source CLAUDE.md not found: $DOTFILES_CLAUDE_MD"
        return 1
    fi
    
    # Backup existing CLAUDE.md if it exists
    if [[ -f "$CLAUDE_MD" ]]; then
        local claude_backup="$DOTFILES_BACKUP_PREFIX/CLAUDE.md.$(date +%Y%m%d_%H%M%S)"
        log_info "Backing up existing CLAUDE.md to: $claude_backup"
        mkdir -p "$DOTFILES_BACKUP_PREFIX"
        cp "$CLAUDE_MD" "$claude_backup"
    fi
    
    # Copy new CLAUDE.md
    log_info "Copying CLAUDE.md from dotfiles..."
    cp "$DOTFILES_CLAUDE_MD" "$CLAUDE_MD"
    
    if [[ -f "$CLAUDE_MD" ]]; then
        log_success "Successfully updated CLAUDE.md"
    else
        log_error "Failed to copy CLAUDE.md"
        return 1
    fi
    
    # Cleanup old CLAUDE.md backups (keep last 5)
    if [[ -d "$DOTFILES_BACKUP_PREFIX" ]]; then
        local old_backups=$(ls -t "$DOTFILES_BACKUP_PREFIX"/CLAUDE.md.* 2>/dev/null | tail -n +6)
        if [[ -n "$old_backups" ]]; then
            log_info "Cleaning up old CLAUDE.md backups..."
            echo "$old_backups" | xargs rm -f
        fi
    fi
}

# Run the updates
update_claude_commands
update_claude_md