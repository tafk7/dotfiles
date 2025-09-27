#!/bin/bash
# Core utilities for simplified dotfiles installation
# Ubuntu-only support, human-readable, well-engineered

# Prevent double-sourcing
[[ -n "${DOTFILES_CORE_LOADED:-}" ]] && return 0
readonly DOTFILES_CORE_LOADED=1

set -e

# Path setup
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../" && pwd)}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
wsl_log() { echo -e "${PURPLE}[WSL]${NC} $1"; }

# =============================================================================
# Core Functions (original core.sh)
# =============================================================================

# Safe sudo wrapper - shows commands before execution
safe_sudo() {
    log "Executing: sudo $*"
    sudo "$@"
}


# Detect Ubuntu version and WSL
detect_environment() {
    if ! command -v lsb_release >/dev/null 2>&1; then
        error "This script requires Ubuntu. lsb_release not found."
        exit 1
    fi
    
    local ubuntu_version=$(lsb_release -rs)
    local ubuntu_codename=$(lsb_release -cs)
    
    log "Detected Ubuntu $ubuntu_version ($ubuntu_codename)"
    
    if is_wsl; then
        wsl_log "Running on Windows Subsystem for Linux"
        local win_user=$(get_windows_username)
        wsl_log "Windows username: $win_user"
    fi
    
    export IS_WSL=$(is_wsl && echo "true" || echo "false")
}

# Process git config template with user input
process_git_config() {
    local source="$1"
    local target="$2"
    local backup_dir="$3"
    
    # Backup existing config if it exists
    if [[ -f "$target" && ! -L "$target" ]]; then
        log "Backing up existing git config"
        mv "$target" "$backup_dir/"
    elif [[ -L "$target" ]]; then
        rm "$target"
    fi
    
    # Get user information
    local git_name git_email
    
    if [[ -t 0 ]]; then  # Interactive terminal
        read -p "Enter your git name: " git_name
        read -p "Enter your git email: " git_email
    else
        # Non-interactive fallback
        git_name="${USER}"
        git_email="${USER}@localhost"
        warn "Non-interactive mode: using default git config ($git_name, $git_email)"
    fi
    
    # Process template
    sed -e "s/{{GIT_NAME}}/$git_name/g" -e "s/{{GIT_EMAIL}}/$git_email/g" "$source" > "$target"
    success "Git config created: $target"
}

# Setup NPM global directory (consolidated function)
setup_npm_global() {
    if ! command -v npm >/dev/null 2>&1; then
        return 0
    fi
    
    log "Setting up NPM global directory..."
    
    # Force Unix-style path on WSL
    local npm_global_dir="$HOME/.npm-global"
    if [[ "$IS_WSL" == "true" ]]; then
        # Ensure we use Linux path, not Windows path
        npm_global_dir="$(cd ~ && pwd)/.npm-global"
    fi
    
    mkdir -p "$npm_global_dir"
    
    # Configure npm to use our global directory
    npm config set prefix "$npm_global_dir"
    
    # Verify the prefix was set correctly
    local actual_prefix=$(npm config get prefix)
    if [[ "$actual_prefix" =~ \\\\ ]]; then
        warn "NPM prefix contains Windows path: $actual_prefix"
        warn "Forcing Unix-style path..."
        # Force set with explicit Unix path
        npm config set prefix "$(cd ~ && pwd)/.npm-global"
    fi
    
    # Add to PATH if not already there
    if [[ ":$PATH:" != *":$npm_global_dir/bin:"* ]]; then
        export PATH="$npm_global_dir/bin:$PATH"
    fi
    
    success "NPM global directory configured: $npm_global_dir"
}

# Validation functions
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check for required commands
    local required_commands=("curl" "wget" "git")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "Required command not found: $cmd"
            exit 1
        fi
    done
    
    # Check bash version
    if [[ ${BASH_VERSION%%.*} -lt 4 ]]; then
        error "Bash 4.0+ required (found: $BASH_VERSION)"
        exit 1
    fi
    
    # Check available disk space (need at least 100MB)
    local available_kb=$(df "$HOME" | awk 'NR==2 {print $4}')
    local required_kb=102400  # 100MB
    
    if [[ $available_kb -lt $required_kb ]]; then
        error "Insufficient disk space. Need 100MB, have $(($available_kb/1024))MB"
        exit 1
    fi
    
    success "Prerequisites validated"
}

# Post-installation validation
validate_installation() {
    log "Validating installation..."
    
    local failed_validations=0
    
    # Check critical files (some are symlinks, .gitconfig is templated)
    local critical_files=("$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.config/nvim/init.vim" "$HOME/.gitconfig")
    for file in "${critical_files[@]}"; do
        if [[ "$file" == "$HOME/.gitconfig" ]]; then
            # .gitconfig is a templated file, not a symlink
            if [[ ! -f "$file" ]]; then
                error "Git config file missing: $file"
                ((failed_validations++))
            elif [[ ! -r "$file" ]]; then
                error "Git config file not readable: $file"
                ((failed_validations++))
            fi
        else
            # All other files should be symlinks
            if [[ ! -L "$file" ]]; then
                error "Critical symlink missing: $file"
                ((failed_validations++))
            else
                # Validate symlink target exists and is readable
                if [[ ! -r "$file" ]]; then
                    error "Symlink target not readable: $file -> $(readlink "$file")"
                    ((failed_validations++))
                fi
            fi
        fi
    done
    
    # Check shell configuration loading
    if [[ -f "$HOME/.bashrc" ]]; then
        if ! grep -q "DOTFILES_DIR" "$HOME/.bashrc"; then
            warn "Dotfiles integration may not be working in .bashrc - DOTFILES_DIR not found"
        fi
    fi
    
    
    if [[ $failed_validations -eq 0 ]]; then
        success "Installation validation passed"
        return 0
    else
        error "Installation validation failed ($failed_validations issues)"
        return 1
    fi
}

# =============================================================================
# WSL Functions (from wsl.sh)
# =============================================================================

# Check if running on WSL
is_wsl() {
    [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]] || [[ -n "${WSL_DISTRO_NAME:-}" ]]
}

# Get Windows username for WSL operations
get_windows_username() {
    if is_wsl; then
        # Use cmd.exe to get Windows username - simple and reliable
        local win_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' | tr -d ' ')
        
        # Validate it's not empty or a system account
        if [[ -z "$win_user" ]] || [[ "$win_user" == "SYSTEM" ]] || [[ "$win_user" == "Administrator" ]]; then
            # Fallback to current user
            win_user="$USER"
        fi
        
        echo "$win_user"
    fi
}

# Setup WSL clipboard integration  
setup_wsl_clipboard() {
    if ! is_wsl; then
        return 0
    fi
    
    wsl_log "Setting up WSL clipboard integration..."
    
    local bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir"
    
    # Create pbcopy script
    cat > "$bin_dir/pbcopy" << 'EOF'
#!/bin/bash
clip.exe
EOF
    
    # Create pbpaste script  
    cat > "$bin_dir/pbpaste" << 'EOF'
#!/bin/bash
powershell.exe -command "Get-Clipboard" | sed 's/\r$//'
EOF
    
    chmod +x "$bin_dir/pbcopy" "$bin_dir/pbpaste"
    
    # Ensure ~/.local/bin is in PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        export PATH="$HOME/.local/bin:$PATH"
    fi
    
    success "WSL clipboard integration setup complete"
}

# Import SSH keys from Windows (WSL only)
import_windows_ssh_keys() {
    if ! is_wsl; then
        return 0
    fi
    
    local win_user=$(get_windows_username)
    if [[ -z "$win_user" ]]; then
        warn "Could not determine Windows username for SSH key import"
        return 1
    fi
    
    local windows_ssh_dir="/mnt/c/Users/$win_user/.ssh"
    
    if [[ ! -d "$windows_ssh_dir" ]]; then
        wsl_log "No Windows SSH directory found at $windows_ssh_dir"
        return 0
    fi
    
    wsl_log "Importing SSH keys from Windows..."
    
    local ssh_dir="$HOME/.ssh"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    
    # Copy SSH keys with proper permissions
    for key_file in "$windows_ssh_dir"/*; do
        if [[ -f "$key_file" ]]; then
            local filename=$(basename "$key_file")
            local target="$ssh_dir/$filename"
            
            cp "$key_file" "$target"
            
            # Set appropriate permissions
            if [[ "$filename" == *.pub ]]; then
                chmod 644 "$target"
            else
                chmod 600 "$target"
            fi
            
            wsl_log "Imported SSH key: $filename"
        fi
    done
    
    success "SSH key import completed"
}

# =============================================================================
# Backup Functions (from backup.sh)
# =============================================================================

# Backup directory within the repository
if [[ -z "${DOTFILES_BACKUP_PREFIX:-}" ]]; then
    readonly DOTFILES_BACKUP_PREFIX="$DOTFILES_DIR/.backups"
fi

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
    
    # If target exists and is not a symlink, back it up
    if [[ -e "$target" && ! -L "$target" ]]; then
        log "Backing up existing $target"
        mv "$target" "$backup_dir/"
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

# Export commonly used functions
export -f is_wsl get_windows_username