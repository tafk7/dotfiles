#!/bin/bash
# Core utilities for simplified dotfiles installation
# Ubuntu-only support, human-readable, well-engineered

# Prevent double-sourcing
[[ -n "${DOTFILES_CORE_LOADED:-}" ]] && return 0
readonly DOTFILES_CORE_LOADED=1

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
wsl_log() { echo -e "${PURPLE}[WSL]${NC} $1"; }

# Check if running on WSL
is_wsl() {
    [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]] || [[ -n "${WSL_DISTRO_NAME:-}" ]]
}

# Get Windows username for WSL operations
get_windows_username() {
    if is_wsl; then
        # Try multiple methods to get Windows username
        local win_user=""
        
        # Method 1: From /mnt/c/Users directory
        if [[ -d "/mnt/c/Users" ]]; then
            win_user=$(ls /mnt/c/Users | grep -v "^Public$" | grep -v "^Default" | head -1)
        fi
        
        # Method 2: From environment variables if available
        if [[ -z "$win_user" && -n "${LOGNAME:-}" ]]; then
            win_user="$LOGNAME"
        fi
        
        # Method 3: From current user as fallback
        if [[ -z "$win_user" ]]; then
            win_user="$USER"
        fi
        
        echo "$win_user"
    fi
}

# Safe sudo wrapper - shows commands before execution
safe_sudo() {
    log "Executing: sudo $*"
    sudo "$@"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Detect Ubuntu version and WSL
detect_environment() {
    if ! command_exists lsb_release; then
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

# Path constants  
if [[ -z "${DOTFILES_BACKUP_PREFIX:-}" ]]; then
    readonly DOTFILES_BACKUP_PREFIX="$HOME/dotfiles-backup"
fi

# Create backup directory with timestamp
create_backup_dir() {
    local backup_dir="$DOTFILES_BACKUP_PREFIX-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    echo "$backup_dir"
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

# Setup NPM global directory (consolidated function)
setup_npm_global() {
    if ! command_exists npm; then
        return 0
    fi
    
    log "Setting up NPM global directory..."
    
    local npm_global_dir="$HOME/.npm-global"
    mkdir -p "$npm_global_dir"
    
    # Configure npm to use our global directory
    npm config set prefix "$npm_global_dir"
    
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
        if ! command_exists "$cmd"; then
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
    
    # Check critical symlinks
    local critical_files=("$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.config/nvim/init.vim" "$HOME/.gitconfig")
    for file in "${critical_files[@]}"; do
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