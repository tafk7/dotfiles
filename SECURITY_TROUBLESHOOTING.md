# Security Troubleshooting Guide

This guide helps resolve common security-related issues during dotfiles installation and usage.

## Download Verification Failures

### Problem: "Checksum verification failed"

**Symptoms:**
```
[ERROR] Checksum verification failed for Cascadia Code font
Expected: ee7c9fe7db17c790e9f924b6c44ec3dda8e40dd18e2cb1ba3dd8f2d5e2ca5458
Actual:   a1b2c3d4e5f6789...
```

**Causes & Solutions:**

1. **Network Issues/Corrupted Download**
   ```bash
   # Clear cache and retry
   rm -rf /tmp/dotfiles-* ~/.cache/dotfiles/
   ./install.sh --force
   ```

2. **Outdated Hash (New Version Released)**
   ```bash
   # Check for dotfiles updates
   git pull origin main
   
   # If hash is still wrong, calculate correct hash:
   curl -L https://github.com/microsoft/cascadia-code/releases/download/v2111.01/CascadiaCode-2111.01.zip | sha256sum
   ```

3. **Proxy/Corporate Network**
   ```bash
   # Set proper proxy if needed
   export https_proxy=http://proxy.company.com:8080
   export http_proxy=http://proxy.company.com:8080
   
   # Try installation
   ./install.sh
   ```

### Problem: "Cannot reach URL"

**Symptoms:**
```
[ERROR] Cannot reach URL: https://raw.githubusercontent.com/...
```

**Solutions:**

1. **Check Internet Connection**
   ```bash
   # Test basic connectivity
   ping -c 3 github.com
   curl -I https://github.com
   ```

2. **DNS Issues**
   ```bash
   # Try different DNS
   echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
   # Or use systemd-resolved
   sudo systemctl restart systemd-resolved
   ```

3. **Firewall/Corporate Restrictions**
   ```bash
   # Skip problematic downloads temporarily
   ./install.sh --skip-existing
   
   # Manual installation later:
   # Download manually and place in correct location
   ```

## SSH Key Import Issues

### Problem: "Invalid SSH key"

**Symptoms:**
```
[WSL] Invalid SSH key, skipping: id_rsa
[ERROR] Source key validation failed: /mnt/c/Users/user/.ssh/id_rsa
```

**Solutions:**

1. **Check Key Format**
   ```bash
   # Verify key format (should start with specific headers)
   head -1 /mnt/c/Users/$(whoami)/.ssh/id_rsa
   # Should show: -----BEGIN OPENSSH PRIVATE KEY-----
   
   head -1 /mnt/c/Users/$(whoami)/.ssh/id_rsa.pub
   # Should show: ssh-rsa AAAAB3... or ssh-ed25519 AAAAC3...
   ```

2. **Permission Issues**
   ```bash
   # Fix Windows SSH permissions
   cd /mnt/c/Users/$(whoami)/.ssh/
   # Keys should be readable
   ls -la id_*
   
   # If needed, copy manually with proper validation
   cp id_rsa ~/.ssh/ && chmod 600 ~/.ssh/id_rsa
   ssh-keygen -l -f ~/.ssh/id_rsa  # Verify key
   ```

3. **Corrupted Keys**
   ```bash
   # Test key validity
   ssh-keygen -l -f /mnt/c/Users/$(whoami)/.ssh/id_rsa
   
   # If invalid, regenerate:
   ssh-keygen -t ed25519 -C "your.email@example.com"
   ```

### Problem: "SSH config file appears invalid"

**Symptoms:**
```
[WSL] SSH config file appears invalid, skipping
```

**Solutions:**

1. **Validate SSH Config**
   ```bash
   # Test config syntax
   ssh -F /mnt/c/Users/$(whoami)/.ssh/config -T git@github.com 2>&1 | head -5
   
   # Check for common issues
   grep -E '^[[:space:]]+(Host|HostName)' /mnt/c/Users/$(whoami)/.ssh/config
   ```

2. **Common Config Issues**
   ```bash
   # Check for Windows line endings
   file /mnt/c/Users/$(whoami)/.ssh/config
   
   # Convert if needed
   dos2unix /mnt/c/Users/$(whoami)/.ssh/config
   ```

## Package Installation Failures

### Problem: "Package not found in repositories"

**Symptoms:**
```
[WARNING] Package not found in repositories: eza
[ERROR] Failed to install base packages after retries
```

**Solutions:**

1. **Update Package Lists**
   ```bash
   # Ubuntu/Debian
   sudo apt update
   
   # Fedora
   sudo dnf update
   
   # Arch
   sudo pacman -Sy
   ```

2. **Enable Required Repositories**
   ```bash
   # Ubuntu: Enable universe repository
   sudo add-apt-repository universe
   
   # Install from alternative sources
   # For eza: cargo install eza
   # For bat: cargo install bat
   ```

3. **Skip Missing Packages**
   ```bash
   # Continue installation without problematic packages
   ./install.sh --skip-existing
   
   # Install missing tools manually later
   ```

### Problem: "Azure CLI installation failed"

**Symptoms:**
```
[ERROR] Failed to download Microsoft signing key
[WARNING] Azure CLI installation may have failed
```

**Solutions:**

1. **Manual Repository Setup**
   ```bash
   # Ubuntu/Debian
   curl -sL https://packages.microsoft.com/keys/microsoft.asc | 
       gpg --dearmor | 
       sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
   
   echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" | 
       sudo tee /etc/apt/sources.list.d/azure-cli.list
   
   sudo apt update && sudo apt install azure-cli
   ```

2. **Alternative Installation Methods**
   ```bash
   # Using pip
   pip3 install --user azure-cli
   
   # Using snap
   sudo snap install azure-cli --classic
   
   # Using conda
   conda install -c conda-forge azure-cli
   ```

## Permission Issues

### Problem: "Permission denied" during installation

**Symptoms:**
```
[ERROR] Permission denied: /home/user/.ssh/config
mkdir: cannot create directory '/home/user/.local': Permission denied
```

**Solutions:**

1. **Check Sudo Access**
   ```bash
   # Verify sudo works
   sudo echo "Sudo access confirmed"
   
   # If sudo password expired
   sudo -v  # Refresh sudo timestamp
   ```

2. **Home Directory Permissions**
   ```bash
   # Check home directory ownership
   ls -la ~
   
   # Fix if needed
   sudo chown -R $(whoami):$(whoami) ~
   ```

3. **SELinux Issues (Fedora/RHEL)**
   ```bash
   # Check SELinux status
   getenforce
   
   # Temporarily disable if causing issues
   sudo setenforce 0
   
   # Re-run installation, then re-enable
   sudo setenforce 1
   ```

## Configuration Issues

### Problem: "Git configuration needs user information"

**Symptoms:**
```
[INFO] Git configuration needs user information...
Enter your full name: [hangs]
```

**Solutions:**

1. **Non-Interactive Mode**
   ```bash
   # Skip interactive setup
   ./install.sh --force
   
   # Configure manually later
   git config --global user.name "Your Name"
   git config --global user.email "your.email@example.com"
   ```

2. **Pre-configure Git**
   ```bash
   # Set before installation
   git config --global user.name "Your Name"
   git config --global user.email "your.email@example.com"
   
   # Then run installation
   ./install.sh
   ```

### Problem: "Tmux config syntax invalid"

**Symptoms:**
```
[WARNING] Tmux configuration may be invalid, proceeding anyway
```

**Solutions:**

1. **Test Tmux Config**
   ```bash
   # Test configuration
   tmux -f ~/.tmux.conf list-keys > /dev/null
   echo $?  # Should be 0 if valid
   ```

2. **Common Fixes**
   ```bash
   # Check tmux version compatibility
   tmux -V
   
   # Update tmux if very old
   sudo apt install tmux  # or appropriate package manager
   ```

## Network Security Issues

### Problem: "Only HTTPS URLs allowed"

**Symptoms:**
```
[ERROR] Only HTTPS URLs allowed: http://example.com/file
```

**This is expected behavior** - the security system blocks HTTP downloads. Solutions:

1. **Check for HTTPS Alternative**
   ```bash
   # Often the same URL works with HTTPS
   curl -I https://example.com/file
   ```

2. **Temporary Bypass (Not Recommended)**
   ```bash
   # Only if you absolutely trust the source
   # Edit the security function temporarily
   # Better: Report the issue so we can add HTTPS support
   ```

## WSL-Specific Issues

### Problem: "Windows SSH directory not found"

**Symptoms:**
```
[WSL] Windows SSH directory not found at /mnt/c/Users/user/.ssh
```

**Solutions:**

1. **Check Username Mapping**
   ```bash
   # Check actual username
   ls /mnt/c/Users/
   
   # If different, set manually
   export WIN_HOME="/mnt/c/Users/ActualUsername"
   ```

2. **Drive Mounting Issues**
   ```bash
   # Check if C: drive is mounted
   ls /mnt/c/
   
   # If not mounted, check WSL configuration
   cat /etc/wsl.conf
   ```

3. **Create SSH Directory**
   ```bash
   # Create if doesn't exist
   mkdir -p "/mnt/c/Users/$(whoami)/.ssh"
   
   # Generate keys in Windows
   cd "/mnt/c/Users/$(whoami)/.ssh"
   ssh-keygen -t ed25519 -C "your.email@example.com"
   ```

## Recovery Procedures

### Rollback Installation

If installation fails catastrophically:

```bash
# Find backup directory
ls -la ~/dotfiles-backup-*

# Restore from backup
BACKUP_DIR=~/dotfiles-backup-20250630-143022  # Use actual timestamp
cp -r $BACKUP_DIR/.zshrc ~/.zshrc
cp -r $BACKUP_DIR/.ssh ~/.ssh
# Restore other files as needed

# Remove problematic symlinks
find ~ -maxdepth 1 -name ".*" -type l -delete
```

### Reset to Clean State

```bash
# Remove all dotfiles configurations
rm -f ~/.zshrc ~/.tmux.conf ~/.gitconfig ~/.vimrc

# Remove symlinks in ~/.local/bin
find ~/.local/bin -type l -delete

# Clean up temporary files
rm -rf /tmp/dotfiles-* ~/.cache/dotfiles/

# Start fresh
git clone <dotfiles-repo> && cd dotfiles
./install.sh
```

### Debug Mode

For detailed troubleshooting:

```bash
# Enable debug output
set -x  # Before running commands

# Run with maximum verbosity
bash -x ./install.sh

# Check specific functions
source scripts/security/core.sh
verify_download "https://example.com/file" "expected-hash" "/tmp/test"
```

## Getting Help

### Log Analysis

```bash
# Check system logs
journalctl --user -n 50

# Check installation logs
# (Installation logs are printed to stdout/stderr)

# Debug specific commands
type psg      # Check if function loaded
which eza     # Check if tool installed
```

### Reporting Issues

When reporting problems, include:

1. **System Information**
   ```bash
   cat /etc/os-release
   echo $SHELL
   tmux -V
   git --version
   ```

2. **Error Context**
   - Exact error message
   - Command that failed
   - Installation mode used (interactive/force/skip)

3. **Environment**
   - WSL version (if applicable)
   - Network environment (corporate/home)
   - Any customizations made

### Manual Override

If automated installation continues to fail:

```bash
# Install core tools manually
sudo apt install zsh tmux git curl wget  # Adjust for your distro

# Symlink only essential configs
ln -sf $PWD/configs/.zshrc ~/.zshrc
ln -sf $PWD/configs/.tmux.conf ~/.tmux.conf

# Configure shell
chsh -s $(which zsh)

# Install Oh My Zsh manually
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

This allows you to get a basic working environment while troubleshooting specific issues.