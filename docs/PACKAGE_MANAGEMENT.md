# Package Management Documentation

This document describes the enhanced package management features in the dotfiles installation system.

## Overview

The package management system provides:
- **Cross-distribution package validation** with name mapping
- **Version constraint management** for specific package requirements
- **Offline installation support** with local package caching
- **Dependency checking** before installation
- **Smart installation** with cache-first approach

## Features

### 1. Package Validation (`scripts/install/package_validator.sh`)

Validates package availability and dependencies before installation.

#### Features:
- **Repository Updates**: Automatically updates package manager cache
- **Availability Check**: Verifies packages exist in repositories
- **Dependency Resolution**: Checks and reports missing dependencies
- **Version Constraints**: Validates version requirements (>=, <=, =, etc.)
- **Similar Package Suggestions**: Suggests alternatives when packages not found
- **System Compatibility**: Checks disk space, network, sudo access

#### Usage:
```bash
# Validate single package
validate_package_availability "nodejs"

# Check dependencies
check_package_dependencies "docker"

# Validate version constraint
validate_version_constraint "git" ">=2.25"

# Validate package list
packages=("git" "tmux>=3.0" "vim")
validate_package_list packages "apt" true  # strict mode
```

### 2. Package Cache System (`scripts/install/package_cache.sh`)

Enables offline installation through local package caching.

#### Features:
- **Local Package Cache**: Downloads and stores packages locally
- **Offline Mode**: Install without internet connection
- **Smart Installation**: Uses cache when available, falls back to repository
- **Cache Management**: Clean old packages, export/import cache
- **Metadata Tracking**: Version, size, date for all cached packages

#### Cache Structure:
```
~/.dotfiles_cache/
├── packages/
│   ├── apt/         # Debian/Ubuntu packages
│   ├── dnf/         # Fedora/RHEL packages
│   └── pacman/      # Arch packages
├── metadata.json    # Cache metadata
└── config          # Cache configuration
```

#### Usage:
```bash
# Initialize cache
manage_cache init

# Cache specific packages
packages=("git" "vim" "tmux")
cache_package_list packages

# Enable offline mode
./install.sh --offline

# Pre-cache for offline use
./install.sh --cache-only

# Install with smart caching
smart_install_package "nodejs"

# Cache management
manage_cache status     # Show cache info
manage_cache clean 7    # Remove packages older than 7 days
manage_cache export     # Export cache for sharing
manage_cache import cache.tar.gz  # Import cache
```

### 3. Cross-Distribution Package Mappings

Handles package name differences across distributions.

#### Configuration File: `configs/package_mappings.json`
```json
{
    "mappings": {
        "build-tools": {
            "apt": "build-essential",
            "dnf": ["make", "gcc", "gcc-c++"],
            "pacman": "base-devel"
        }
    }
}
```

#### Usage:
```bash
# Resolve package name for current distribution
resolved_name=$(resolve_package_name "build-tools" "apt")
# Returns: "build-essential"
```

## Installation Modes

### Standard Installation
```bash
./install.sh
```
- Validates packages before installation
- Uses cache when available
- Downloads from repository if needed
- Automatically caches installed packages

### Offline Installation
```bash
# First, cache packages while online
./install.sh --cache-only

# Later, install offline
./install.sh --offline
```

### Force Cache Rebuild
```bash
# Clear and rebuild cache
manage_cache clean 0  # Remove all
manage_cache precache # Cache essentials
```

## Advanced Features

### 1. Version Constraint Validation

Supports standard version constraint operators:
- `=` or `==` - Exact version
- `>` - Greater than
- `>=` - Greater than or equal
- `<` - Less than  
- `<=` - Less than or equal

Example:
```bash
validate_version_constraint "nodejs" ">=14.0"
validate_version_constraint "python3" ">=3.8,<4.0"
```

### 2. Dependency Checking

Before installing, check all dependencies:
```bash
check_package_dependencies "docker"
# Output:
# Dependencies:
#   ✓ containerd (installed)
#   ✗ docker-cli (not installed)
```

### 3. System Compatibility Check

Comprehensive pre-installation checks:
```bash
check_system_compatibility
# Checks:
# - Distribution detection
# - Package manager availability
# - Sudo access
# - Network connectivity
# - Disk space (>1GB required)
```

### 4. Package Validation Modes

#### Strict Mode
Fails if any package is invalid:
```bash
validate_package_list packages "apt" true
```

#### Lenient Mode
Continues with valid packages only:
```bash
validate_package_list packages "apt" false
```

## Configuration

### Environment Variables
```bash
# Cache directory location
export DOTFILES_CACHE_DIR="$HOME/.my_cache"

# Maximum cache age (days)
export CACHE_MAX_AGE_DAYS=60

# Force offline mode
export DOTFILES_OFFLINE_MODE=true
```

### Cache Configuration
Edit `~/.dotfiles_cache/config`:
```bash
CACHE_ENABLED=true        # Enable/disable caching
OFFLINE_MODE=false        # Force offline mode
AUTO_CACHE=true          # Auto-cache installed packages
VERIFY_CHECKSUMS=true    # Verify package integrity
MAX_CACHE_SIZE_GB=10     # Maximum cache size
```

## Troubleshooting

### Package Not Found
```bash
# Check repository update
update_repository_info

# Search for similar packages
apt-cache search packagename
```

### Cache Issues
```bash
# Verify cache integrity
manage_cache status

# Clear corrupted cache
rm -rf ~/.dotfiles_cache
manage_cache init
```

### Offline Installation Fails
```bash
# Check cached packages
ls ~/.dotfiles_cache/packages/

# Verify specific package
is_package_cached "package-name"

# Force re-cache
download_package "package-name"
```

### Version Mismatch
```bash
# Check available version
get_package_version "package-name"

# Update cache with latest
download_package "package-name"
```

## Performance Tips

1. **Pre-cache before going offline**
   ```bash
   ./install.sh --cache-only
   ```

2. **Regular cache cleanup**
   ```bash
   # Add to crontab
   0 0 * * 0 manage_cache clean 30
   ```

3. **Export cache for multiple machines**
   ```bash
   manage_cache export dotfiles-cache.tar.gz
   # Copy to other machines
   scp dotfiles-cache.tar.gz user@host:
   # Import on target
   manage_cache import dotfiles-cache.tar.gz
   ```

4. **Optimize cache size**
   ```bash
   # Remove old versions
   manage_cache clean 7
   
   # Show space usage
   du -sh ~/.dotfiles_cache/
   ```

## Security Considerations

1. **Package Verification**: Currently relies on package manager's built-in verification
2. **Cache Permissions**: Cache directory is user-readable only (700)
3. **Offline Risks**: Cached packages may become outdated with security fixes

## Future Enhancements

Planned improvements:
- GPG signature verification for cached packages
- Compression for cache storage
- Delta updates for large packages
- Mirror selection for faster downloads
- Parallel package downloads
- Integration with corporate package proxies