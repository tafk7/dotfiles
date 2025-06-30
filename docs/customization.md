# Dotfiles Customization Guide

This guide explains how to customize and extend the dotfiles system for your specific needs.

## Adding Custom Packages

### 1. Choose the Right Setup Script

- **`base_setup.sh`** - Essential tools that everyone needs (git, curl, vim, etc.)
- **`work_setup.sh`** - Professional development tools (VS Code, Azure CLI, Node.js/Python dev tools)
- **`personal_setup.sh`** - Personal preferences and utilities
- **`ai_setup.sh`** - AI tools (Claude Code and prompts)

### 2. Package Mapping Format

Packages use a cross-distribution mapping format:
```bash
"generic_name:apt_name:dnf_name:pacman_name"
```

Examples:
```bash
"exa:eza:exa:exa"  # Different names across distros
"git:git:git:git"  # Same name across distros
"git"              # Can omit if same across all distros
```

### 3. Adding a New Package

Edit the appropriate setup script and add to the package_mappings array:

```bash
declare -a package_mappings=(
    # ... existing packages ...
    "your-tool:apt-name:dnf-name:pacman-name"
)
```

### 4. Adding npm packages (work_setup.sh)

```bash
declare -a work_npm_packages=("yarn" "typescript" "your-npm-package")
```

### 5. Adding VS Code Extensions (work_setup.sh)

```bash
declare -a work_vscode_extensions=(
    "ms-vscode-remote.remote-wsl"
    "your.extension"
)
```

## Adding Custom Configuration Files

### 1. Add Your Config File

Place your configuration file in the `configs/` directory:
```bash
cp ~/.your-config configs/.your-config
```

### 2. Update Symlink Creation

Edit `scripts/core/files.sh` and add to the configs array in the `create_symlinks()` function:
```bash
local configs=(".gitconfig" ".profile" ".editorconfig" ".ripgreprc" ".vimrc" ".tmux.conf" ".your-config")
```

### 3. Update Backup List

Also in `files.sh`, add to the backup files array in the `backup_existing_configs()` function:
```bash
local files=("... existing files ..." ".your-config")
```

## Adding Custom Aliases or Functions

### 1. Create New Alias File

Create a new file in `scripts/aliases/`:
```bash
touch scripts/aliases/mytools.sh
```

### 2. Add Your Aliases

```bash
#!/bin/bash
# My custom aliases

alias mycommand='some-long-command --with-options'
alias work='cd ~/projects/work'
```

### 3. Automatic Loading

The file will be automatically sourced on shell startup - no additional configuration needed!

## Creating Custom Functions

### 1. Add to Functions Directory

Create a new file in `scripts/functions/`:
```bash
touch scripts/functions/myutils.sh
```

### 2. Define Your Functions

```bash
#!/bin/bash
# My utility functions

# Example: Quick project setup
new-project() {
    local name="$1"
    mkdir -p "$HOME/projects/$name"
    cd "$HOME/projects/$name"
    git init
    echo "# $name" > README.md
}
```

## WSL-Specific Customizations

For WSL-specific aliases or functions, add them to `scripts/aliases/wsl.sh`. They'll only be loaded when running in WSL.

## Framework Functions Available

### Package Management
```bash
# Install packages from mapping array
install_packages package_array "description"

# Install single package
install_single_package "package-name"

# Install npm packages globally
install_npm_packages npm_array "description"

# Install VS Code extensions
install_vscode_extensions extension_array "description"
```

### Security Functions
```bash
# Verify downloaded files
verify_download "$url" "$checksum" "$output_file" "description"

# Validate SSH keys
validate_ssh_key "$key_file"

# Safe sudo execution
safe_sudo command args
```

### Logging
```bash
log "Info message"
success "Success message"
warn "Warning message"
error "Error message"
work_log "Work-specific message"
personal_log "Personal setup message"
```

## Adding Complex Software

For software that requires more than a simple package install:

1. Create a function in the appropriate setup file:
```bash
install_your_software() {
    work_log "Installing Your Software..."
    
    # Download and verify if needed
    local temp_dir=$(mktemp -d)
    local installer="$temp_dir/installer.sh"
    
    if verify_download "$url" "$checksum" "$installer" "Your Software"; then
        chmod +x "$installer"
        "$installer" --options
    else
        error "Failed to download Your Software"
        rm -rf "$temp_dir"
        return 1
    fi
    
    rm -rf "$temp_dir"
    success "Your Software installed"
}

# Call it in the setup
install_your_software || warn "Your Software installation failed"
```


## Testing Your Changes

1. Test on a clean system or container
2. Test each installation mode:
   ```bash
   ./install.sh                    # Base only
   ./install.sh --work            # Base + work
   ./install.sh --personal        # Base + personal
   ./install.sh --work --personal # Everything
   ```

3. Test on different distributions if possible

## Best Practices

1. **Package Names**: Always provide mappings for all three package managers
2. **Error Handling**: Use the provided error handling functions
3. **Security**: Use `verify_download()` for any external downloads
4. **Logging**: Use appropriate log levels for user feedback
5. **Testing**: Test your changes before committing
6. **Documentation**: Update README.md if you add user-facing features

## Testing Your Customizations

1. Run the installer with your preferred options:
   ```bash
   ./install.sh --work --personal
   ```

2. Or reload your shell configuration:
   ```bash
   source ~/.bashrc  # or ~/.zshrc
   ```

3. Use the `reload` alias for quick testing without restarting

## Best Practices

1. **Keep it modular** - Put related aliases/functions in their own files
2. **Use descriptive names** - Make it clear what your customizations do  
3. **Document complex functions** - Add comments explaining usage
4. **Test across distributions** - If sharing, ensure package names work everywhere
5. **Backup first** - The installer creates backups, but manual backups are good too

## Distribution-Specific Notes

### Ubuntu/Debian (apt)
- Use `apt-get` commands with `-y` flag
- Some packages have different names (e.g., `fd-find` instead of `fd`)

### Fedora/RHEL (dnf)
- Use `dnf` commands with `-y` flag
- Enable EPEL repository if needed for RHEL

### Arch/Manjaro (pacman)
- Use `pacman -S --noconfirm`
- AUR packages require an AUR helper like `yay`

## Contributing Back

If you create useful customizations that others might benefit from:

1. Ensure they're generic enough for broad use
2. Test on multiple distributions if adding packages
3. Document any special requirements
4. Submit a pull request with your additions

## Getting Help

If you're unsure about something:
1. Look at existing implementations in the setup files
2. Check the security functions in `scripts/security/core.sh`
3. Test in a safe environment first
4. Follow the patterns used by existing code