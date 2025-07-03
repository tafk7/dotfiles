#!/bin/bash
# Validation helper functions for dotfiles installation
# Ubuntu-only support, comprehensive package and configuration validation

# Prevent double-sourcing
[[ -n "${DOTFILES_VALIDATION_LOADED:-}" ]] && return 0
readonly DOTFILES_VALIDATION_LOADED=1

# Source core functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/core.sh"

# Validation counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNED_TESTS=0

# Test result tracking
declare -a FAILED_RESULTS=()
declare -a WARNED_RESULTS=()

# Colors for validation output
readonly V_PASS='\033[0;32m✅'
readonly V_FAIL='\033[0;31m❌'
readonly V_WARN='\033[1;33m⚠️'
readonly V_INFO='\033[0;34mℹ️'
readonly V_NC='\033[0m'

# Validation logging functions
test_pass() {
    ((TOTAL_TESTS++))
    ((PASSED_TESTS++))
    echo -e "${V_PASS} PASS${V_NC} $1"
}

test_fail() {
    ((TOTAL_TESTS++))
    ((FAILED_TESTS++))
    FAILED_RESULTS+=("$1")
    echo -e "${V_FAIL} FAIL${V_NC} $1"
    [[ -n "${2:-}" ]] && echo -e "  ${V_INFO}${V_NC} Fix: $2"
}

test_warn() {
    ((TOTAL_TESTS++))
    ((WARNED_TESTS++))
    WARNED_RESULTS+=("$1")
    echo -e "${V_WARN} WARN${V_NC} $1"
    [[ -n "${2:-}" ]] && echo -e "  ${V_INFO}${V_NC} Note: $2"
}

test_info() {
    echo -e "${V_INFO} INFO${V_NC} $1"
}

# Check if command exists and is callable
validate_command() {
    local cmd="$1"
    local display_name="${2:-$cmd}"
    local fix_hint="${3:-}"
    
    if command_exists "$cmd"; then
        test_pass "$display_name command available"
        return 0
    else
        test_fail "$display_name command not found" "$fix_hint"
        return 1
    fi
}

# Check if command exists with version output
validate_command_with_version() {
    local cmd="$1"
    local version_flag="${2:---version}"
    local display_name="${3:-$cmd}"
    local fix_hint="${4:-}"
    
    if command_exists "$cmd"; then
        local version_output
        if version_output=$($cmd $version_flag 2>/dev/null | head -1); then
            test_pass "$display_name available: $version_output"
            return 0
        else
            test_warn "$display_name found but version check failed"
            return 1
        fi
    else
        test_fail "$display_name command not found" "$fix_hint"
        return 1
    fi
}

# Check if file or symlink exists and is readable
validate_file_exists() {
    local file="$1"
    local description="${2:-$file}"
    local fix_hint="${3:-}"
    
    if [[ -f "$file" || -L "$file" ]]; then
        if [[ -r "$file" ]]; then
            test_pass "$description exists and is readable"
            return 0
        else
            test_fail "$description exists but is not readable" "$fix_hint"
            return 1
        fi
    else
        test_fail "$description does not exist" "$fix_hint"
        return 1
    fi
}

# Check if symlink points to correct target
validate_symlink() {
    local link="$1"
    local expected_target="$2"
    local description="${3:-$link}"
    
    if [[ -L "$link" ]]; then
        local actual_target=$(readlink -f "$link")
        if [[ "$actual_target" == "$expected_target" ]]; then
            test_pass "$description symlink points to correct target"
            return 0
        else
            test_fail "$description symlink points to wrong target: $actual_target" "Remove and recreate symlink"
            return 1
        fi
    else
        test_fail "$description is not a symlink" "Create symlink to $expected_target"
        return 1
    fi
}

# Check if directory exists
validate_directory() {
    local dir="$1"
    local description="${2:-$dir}"
    local fix_hint="${3:-}"
    
    if [[ -d "$dir" ]]; then
        test_pass "$description directory exists"
        return 0
    else
        test_fail "$description directory does not exist" "$fix_hint"
        return 1
    fi
}

# Check if user is in a group
validate_user_in_group() {
    local group="$1"
    local fix_hint="${2:-}"
    
    if groups | grep -q "\b$group\b"; then
        test_pass "User is in $group group"
        return 0
    else
        test_fail "User is not in $group group" "$fix_hint"
        return 1
    fi
}

# Check if service is running
validate_service_status() {
    local service="$1"
    local description="${2:-$service service}"
    
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        test_pass "$description is running"
        return 0
    elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
        test_warn "$description is enabled but not running" "Start with: sudo systemctl start $service"
        return 1
    else
        test_fail "$service service is not available" "Install and enable $service"
        return 1
    fi
}

# Check if npm global package is installed
validate_npm_global_package() {
    local package="$1"
    local fix_hint="${2:-npm install -g $package}"
    
    if npm list -g "$package" >/dev/null 2>&1; then
        test_pass "NPM global package: $package"
        return 0
    else
        test_fail "NPM global package missing: $package" "$fix_hint"
        return 1
    fi
}

# Check if pip/pipx package is installed
validate_python_package() {
    local package="$1"
    local method="${2:-pipx}"  # pipx or pip
    
    case "$method" in
        "pipx")
            if command_exists pipx && pipx list | grep -q "package $package"; then
                test_pass "Python package (pipx): $package"
                return 0
            else
                test_fail "Python package missing (pipx): $package" "pipx install $package"
                return 1
            fi
            ;;
        "pip")
            if pip3 list --user | grep -q "^$package "; then
                test_pass "Python package (pip --user): $package"
                return 0
            else
                test_fail "Python package missing (pip --user): $package" "pip3 install --user $package"
                return 1
            fi
            ;;
    esac
}

# Validate Oh My Zsh installation
validate_oh_my_zsh() {
    local oh_my_zsh_dir="$HOME/.oh-my-zsh"
    
    if [[ -d "$oh_my_zsh_dir" ]]; then
        test_pass "Oh My Zsh installation directory"
        
        # Check for Powerlevel10k theme
        local p10k_dir="$oh_my_zsh_dir/custom/themes/powerlevel10k"
        if [[ -d "$p10k_dir" ]]; then
            test_pass "Powerlevel10k theme installed"
        else
            test_fail "Powerlevel10k theme missing" "Install with: git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $p10k_dir"
        fi
        
        # Check for plugins
        local plugins_dir="$oh_my_zsh_dir/custom/plugins"
        local required_plugins=("zsh-autosuggestions" "zsh-syntax-highlighting" "zsh-completions")
        
        for plugin in "${required_plugins[@]}"; do
            if [[ -d "$plugins_dir/$plugin" ]]; then
                test_pass "Zsh plugin: $plugin"
            else
                test_fail "Zsh plugin missing: $plugin" "Install with git clone"
            fi
        done
        
        return 0
    else
        test_fail "Oh My Zsh not installed" "Install with the Oh My Zsh installation script"
        return 1
    fi
}

# Validate FZF installation and integration
validate_fzf_integration() {
    if validate_command "fzf" "FZF"; then
        # Check for shell integration files
        local bash_integration="$HOME/.fzf.bash"
        local zsh_integration="$HOME/.fzf.zsh"
        
        if [[ -f "$bash_integration" ]]; then
            test_pass "FZF bash integration file exists"
        else
            test_warn "FZF bash integration file missing" "Run FZF installation script or create manually"
        fi
        
        if [[ -f "$zsh_integration" ]]; then
            test_pass "FZF zsh integration file exists"
        else
            test_warn "FZF zsh integration file missing" "Run FZF installation script or create manually"
        fi
        
        return 0
    else
        return 1
    fi
}

# Validate Docker installation comprehensively
validate_docker_comprehensive() {
    local docker_ok=true
    
    # Check Docker command
    if ! validate_command_with_version "docker" "--version" "Docker"; then
        docker_ok=false
    fi
    
    # Check Docker Compose V2
    if docker compose version >/dev/null 2>&1; then
        local compose_version=$(docker compose version --short 2>/dev/null || echo "unknown")
        test_pass "Docker Compose V2 available: $compose_version"
    else
        test_fail "Docker Compose V2 not available" "Install docker-compose-plugin package"
        docker_ok=false
    fi
    
    # Check Docker daemon
    if docker info >/dev/null 2>&1; then
        test_pass "Docker daemon is accessible"
    else
        test_fail "Docker daemon not accessible" "Start Docker or add user to docker group"
        docker_ok=false
    fi
    
    # Check docker group membership
    validate_user_in_group "docker" "sudo usermod -aG docker \$USER && newgrp docker"
    
    return $([[ "$docker_ok" == "true" ]] && echo 0 || echo 1)
}

# Validate WSL-specific features
validate_wsl_features() {
    if ! is_wsl; then
        test_info "Not running on WSL - skipping WSL-specific validation"
        return 0
    fi
    
    test_info "Validating WSL-specific features..."
    
    # Check WSL packages
    validate_command "socat" "Socat (WSL)" "sudo apt install socat"
    validate_command "wslu" "WSL utilities" "sudo apt install wslu"
    
    # Check clipboard integration
    local clipboard_ok=true
    if validate_file_exists "$HOME/.local/bin/pbcopy" "pbcopy script"; then
        if [[ -x "$HOME/.local/bin/pbcopy" ]]; then
            test_pass "pbcopy script is executable"
        else
            test_fail "pbcopy script is not executable" "chmod +x ~/.local/bin/pbcopy"
            clipboard_ok=false
        fi
    else
        clipboard_ok=false
    fi
    
    if validate_file_exists "$HOME/.local/bin/pbpaste" "pbpaste script"; then
        if [[ -x "$HOME/.local/bin/pbpaste" ]]; then
            test_pass "pbpaste script is executable"
        else
            test_fail "pbpaste script is not executable" "chmod +x ~/.local/bin/pbpaste"
            clipboard_ok=false
        fi
    else
        clipboard_ok=false
    fi
    
    # Check SSH key import
    local win_user=$(get_windows_username)
    if [[ -n "$win_user" ]]; then
        test_pass "Windows username detected: $win_user"
        local windows_ssh_dir="/mnt/c/Users/$win_user/.ssh"
        if [[ -d "$windows_ssh_dir" ]]; then
            test_pass "Windows SSH directory accessible"
            
            # Check if any SSH keys were imported
            if [[ -d "$HOME/.ssh" ]] && ls "$HOME/.ssh"/* >/dev/null 2>&1; then
                test_pass "SSH keys imported to Linux home directory"
            else
                test_warn "No SSH keys found in Linux home directory" "Run: sync-ssh command"
            fi
        else
            test_warn "Windows SSH directory not found" "No SSH keys to import"
        fi
    else
        test_warn "Could not detect Windows username" "WSL integration may be limited"
    fi
    
    return 0
}

# Print validation summary
print_validation_summary() {
    echo
    echo "======================================"
    echo "VALIDATION SUMMARY"
    echo "======================================"
    echo "Total Tests: $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
    echo -e "Warnings: ${YELLOW}$WARNED_TESTS${NC}"
    echo
    
    if [[ $FAILED_TESTS -gt 0 ]]; then
        echo -e "${RED}FAILED TESTS:${NC}"
        for failure in "${FAILED_RESULTS[@]}"; do
            echo "  • $failure"
        done
        echo
    fi
    
    if [[ $WARNED_TESTS -gt 0 ]]; then
        echo -e "${YELLOW}WARNINGS:${NC}"
        for warning in "${WARNED_RESULTS[@]}"; do
            echo "  • $warning"
        done
        echo
    fi
    
    local success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}✅ VALIDATION PASSED${NC} (${success_rate}% success rate)"
        return 0
    else
        echo -e "${RED}❌ VALIDATION FAILED${NC} (${success_rate}% success rate)"
        echo "Please address the failed tests before considering the installation complete."
        return 1
    fi
}