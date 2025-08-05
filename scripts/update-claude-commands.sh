#!/bin/bash
# Update Claude slash commands by syncing from dotfiles to ~/.claude/commands

# Source the core library for logging functions
DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export DOTFILES_DIR
source "$DOTFILES_DIR/lib/core.sh"

# Define paths
DOTFILES_COMMANDS="$DOTFILES_DIR/ai/commands"
CLAUDE_COMMANDS="$HOME/.claude/commands"
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

# Run the update
update_claude_commands