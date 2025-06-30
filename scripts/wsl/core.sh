#!/bin/bash
# Core WSL functionality - simplified and essential features only

# Check if we're in WSL
is_wsl() {
    [[ -f /proc/version ]] && grep -q -i "microsoft\|wsl" /proc/version 2>/dev/null
}

# Get Windows username
get_windows_username() {
    if is_wsl; then
        # Try multiple methods to get Windows username
        local win_user
        
        # Method 1: From Windows environment
        win_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
        
        # Method 2: From WSL interop
        if [[ -z "$win_user" ]] && [[ -n "$WSL_INTEROP" ]]; then
            win_user=$(powershell.exe -NoProfile -Command "Write-Host \$env:USERNAME" 2>/dev/null | tr -d '\r\n')
        fi
        
        # Method 3: Assume same as Linux username
        if [[ -z "$win_user" ]]; then
            win_user="$USER"
        fi
        
        echo "$win_user"
    fi
}

# Convert WSL path to Windows path
wsl_to_windows_path() {
    local wsl_path="$1"
    if is_wsl && command -v wslpath >/dev/null 2>&1; then
        wslpath -w "$wsl_path" 2>/dev/null
    else
        echo "$wsl_path"
    fi
}

# Convert Windows path to WSL path
windows_to_wsl_path() {
    local win_path="$1"
    if is_wsl && command -v wslpath >/dev/null 2>&1; then
        wslpath -u "$win_path" 2>/dev/null
    else
        echo "$win_path"
    fi
}

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

# Import SSH keys from Windows
import_windows_ssh_keys() {
    if ! is_wsl; then
        return 0
    fi
    
    local win_user=$(get_windows_username)
    local win_ssh_dir="/mnt/c/Users/$win_user/.ssh"
    
    if [[ ! -d "$win_ssh_dir" ]]; then
        echo "Windows SSH directory not found: $win_ssh_dir"
        return 1
    fi
    
    # Create Linux SSH directory
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    
    # Import SSH keys with validation
    for key_file in "$win_ssh_dir"/id_*; do
        [[ ! -f "$key_file" ]] && continue
        
        local filename=$(basename "$key_file")
        local dest="$HOME/.ssh/$filename"
        
        # Skip if already exists
        if [[ -f "$dest" ]]; then
            echo "Skipping $filename (already exists)"
            continue
        fi
        
        # Copy with appropriate permissions
        if [[ "$filename" =~ \.pub$ ]]; then
            # Public key
            install -m 644 "$key_file" "$dest"
            echo "Imported public key: $filename"
        else
            # Private key - validate first
            if ssh-keygen -y -f "$key_file" >/dev/null 2>&1; then
                install -m 600 "$key_file" "$dest"
                echo "Imported private key: $filename"
            else
                echo "Skipping invalid key: $filename"
            fi
        fi
    done
    
    # Import known_hosts if exists
    if [[ -f "$win_ssh_dir/known_hosts" ]]; then
        install -m 644 "$win_ssh_dir/known_hosts" "$HOME/.ssh/known_hosts"
        echo "Imported known_hosts"
    fi
    
    # Import config if exists
    if [[ -f "$win_ssh_dir/config" ]]; then
        install -m 644 "$win_ssh_dir/config" "$HOME/.ssh/config"
        echo "Imported SSH config"
    fi
}

# Setup basic WSL environment
setup_wsl_environment() {
    if ! is_wsl; then
        return 0
    fi
    
    # Set browser to use Windows browser
    if command -v wslview >/dev/null 2>&1; then
        export BROWSER=wslview
    fi
    
    # Setup clipboard
    setup_wsl_clipboard
    
    # Add Windows paths to PATH (optional, conservative approach)
    # Only add essential Windows tools
    local win_paths=(
        "/mnt/c/Windows/System32"
        "/mnt/c/Windows"
    )
    
    for path in "${win_paths[@]}"; do
        if [[ -d "$path" ]] && [[ ":$PATH:" != *":$path:"* ]]; then
            export PATH="$PATH:$path"
        fi
    done
}

# WSL-specific aliases (to be sourced by shell)
setup_wsl_aliases() {
    if ! is_wsl; then
        return 0
    fi
    
    # Navigation shortcuts
    alias cdrive='cd /mnt/c'
    alias ddrive='cd /mnt/d'
    alias win-home='cd /mnt/c/Users/$(get_windows_username)'
    
    # Windows integration
    alias explorer='explorer.exe'
    alias code-win='/mnt/c/Program\ Files/Microsoft\ VS\ Code/Code.exe'
    alias open='wslview'
    
    # SSH helpers
    alias win-ssh='ls -la /mnt/c/Users/$(get_windows_username)/.ssh/'
    alias sync-ssh='import_windows_ssh_keys'
}

# Display WSL information
show_wsl_info() {
    if ! is_wsl; then
        echo "Not running in WSL"
        return 0
    fi
    
    echo "WSL Environment Information:"
    echo "- WSL Version: $(uname -r | grep -o 'WSL[0-9]' || echo 'WSL1')"
    echo "- Windows User: $(get_windows_username)"
    echo "- Windows Home: /mnt/c/Users/$(get_windows_username)"
    
    if [[ -d "$HOME/.ssh" ]]; then
        echo "- SSH Keys: $(ls -1 "$HOME/.ssh"/id_* 2>/dev/null | wc -l) found"
    fi
    
    if command -v clip.exe >/dev/null 2>&1; then
        echo "- Clipboard: Available (clip.exe)"
    fi
}