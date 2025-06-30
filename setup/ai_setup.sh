#!/bin/bash
# AI setup script - Claude Code and AI prompt management
# This file is sourced by install.sh when --ai flag is used

# Main AI package installation function
install_ai_packages() {
    log "Installing AI development tools..."
    
    # Install Claude Code
    install_claude_code
    
    # Copy AI prompts to user directory
    setup_ai_prompts
    
    success "AI environment configured"
}

# Install Claude Code via npm
install_claude_code() {
    log "Installing Claude Code..."
    
    # Check if Node.js 18+ is available
    if ! command -v node >/dev/null 2>&1; then
        error "Node.js is required for Claude Code. Install base packages first."
        return 1
    fi
    
    # Check Node.js version
    local node_version=$(node --version | cut -d'.' -f1 | sed 's/v//')
    if [[ $node_version -lt 18 ]]; then
        warn "Claude Code requires Node.js 18 or higher (current: $(node --version))"
        return 1
    fi
    
    # Configure npm to avoid permission issues
    if [[ ! -d "$HOME/.npm-global" ]]; then
        mkdir -p "$HOME/.npm-global"
        npm config set prefix "$HOME/.npm-global"
        
        # Add to PATH if not already present
        if ! grep -q ".npm-global/bin" "$HOME/.bashrc" 2>/dev/null && \
           ! grep -q ".npm-global/bin" "$HOME/.zshrc" 2>/dev/null; then
            log "Adding npm global bin to PATH..."
            # Use .zshrc if it exists, otherwise .bashrc
            local shell_config="$HOME/.bashrc"
            [[ -f "$HOME/.zshrc" ]] && shell_config="$HOME/.zshrc"
            echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$shell_config"
        fi
    fi
    
    # Install Claude Code globally
    if npm install -g @anthropic-ai/claude-code; then
        success "Claude Code installed successfully"
        log "Authenticate with: claude --auth"
        log "Or set: export ANTHROPIC_API_KEY=your_key_here"
    else
        error "Failed to install Claude Code"
        return 1
    fi
}

# Setup AI prompts
setup_ai_prompts() {
    log "Setting up AI prompts..."
    
    local ai_source_dir="$DOTFILES_DIR/ai"
    local ai_target_dir="$HOME/.claude"
    
    # Create target directory
    mkdir -p "$ai_target_dir"
    
    # Copy all AI prompt files
    if [[ -d "$ai_source_dir" ]]; then
        log "Copying AI prompts to $ai_target_dir..."
        
        # Copy all .md files from ai/ directory
        local copied_count=0
        for prompt_file in "$ai_source_dir"/*.md; do
            if [[ -f "$prompt_file" ]]; then
                local filename=$(basename "$prompt_file")
                cp "$prompt_file" "$ai_target_dir/$filename"
                ((copied_count++))
                log "Copied: $filename"
            fi
        done
        
        if [[ $copied_count -gt 0 ]]; then
            success "Copied $copied_count AI prompt files to $ai_target_dir"
            log "Access your prompts with: ls ~/.claude/"
        else
            warn "No AI prompt files found to copy"
        fi
    else
        warn "AI prompts directory not found: $ai_source_dir"
    fi
}