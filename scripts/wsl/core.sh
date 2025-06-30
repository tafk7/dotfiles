#!/bin/bash
# Core WSL functionality - simplified and essential features only

# Source common utilities if not already loaded
if ! declare -f is_wsl >/dev/null 2>&1; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../core/common.sh"
fi


# Simple clipboard integration
setup_wsl_clipboard() {
    if ! is_wsl; then
        return 0
    fi
    
    # Create pbcopy/pbpaste functions
    cat > "$HOME/.local/bin/pbcopy" << 'EOF'
#!/bin/bash
# Copy to Windows clipboard
if command -v clip.exe >/dev/null 2>&1; then
    clip.exe
elif command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command "Set-Clipboard -Value \$input"
else
    echo "Error: No clipboard command available" >&2
    exit 1
fi
EOF
    
    cat > "$HOME/.local/bin/pbpaste" << 'EOF'
#!/bin/bash
# Paste from Windows clipboard
if command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command "Get-Clipboard" | tr -d '\r'
else
    echo "Error: No clipboard command available" >&2
    exit 1
fi
EOF
    
    chmod +x "$HOME/.local/bin/pbcopy" "$HOME/.local/bin/pbpaste"
}

# SSH key import functionality moved to scripts/security/ssh.sh


# WSL-specific aliases (to be sourced by shell)
setup_wsl_aliases() {
    if ! is_wsl; then
        return 0
    fi
    
    local win_user=$(get_windows_username)
    
    # Navigation shortcuts
    alias cdrive='cd /mnt/c'
    alias ddrive='cd /mnt/d'
    alias win-home="cd /mnt/c/Users/$win_user"
    
    # Windows integration
    alias explorer='explorer.exe'
    alias code-win='/mnt/c/Program\ Files/Microsoft\ VS\ Code/Code.exe'
    alias open='wslview'
    
    # SSH helpers
    alias win-ssh="ls -la /mnt/c/Users/$win_user/.ssh/"
}

