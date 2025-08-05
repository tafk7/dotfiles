# Core.sh Usage Analysis

## Overview
This analysis examines which functions and variables from `lib/core.sh` are actually used throughout the dotfiles repository.

## Files That Source core.sh

### Direct Sources
1. **install.sh** - Main installer script
2. **lib/packages.sh** - Package management module
3. **lib/validation.sh** - Validation framework
4. **scripts/validate-install.sh** - Installation validator
5. **scripts/theme-switcher.sh** - Theme management
6. **scripts/update-configs.sh** - Configuration updater

### Indirect References
- Various scripts reference core.sh in documentation but don't source it
- Theme files use logging functions but inherit them from parent scripts

## Function Usage Frequency

### Most Used Functions
1. **log()** - 47 occurrences
   - General logging throughout installation and configuration
   - Most common in install.sh and packages.sh

2. **warn()** - 31 occurrences
   - Warning messages for non-critical issues
   - Used heavily in package availability checks

3. **error()** - 28 occurrences
   - Error reporting for critical failures
   - Common in validation and symlink operations

4. **success()** - 26 occurrences
   - Success messages after completing operations
   - Used to confirm installations and configurations

5. **safe_sudo()** - 10 occurrences
   - Primarily for apt operations
   - Used in package installations

### Moderately Used Functions
- **safe_symlink()** - Used for creating configuration symlinks
- **command_exists()** - Checking for installed commands
- **detect_environment()** - Called during initialization
- **create_backup_dir()** - Creates backup directories
- **backup_file()** - Backs up existing files before overwriting
- **process_git_config()** - Special handling for .gitconfig
- **cleanup_old_backups()** - Maintains backup directory

### WSL-Specific Functions
- **is_wsl()** - Determines if running in WSL
- **wsl_log()** - WSL-specific logging
- **get_windows_username()** - Retrieves Windows username
- **setup_wsl_clipboard()** - Sets up clipboard integration
- **import_windows_ssh_keys()** - Imports SSH keys from Windows

### Installation Functions
- **validate_prerequisites()** - Checks system requirements
- **validate_installation()** - Post-installation validation
- **setup_npm_global()** - Configures npm global directory

## Variable Usage

### Environment Variables
- **IS_WSL** - Set by detect_environment(), used in packages.sh and validation.sh
- **DOTFILES_BACKUP_PREFIX** - Used for backup directory naming

### Color Variables
Core.sh defines these color variables that are used throughout:
- **RED, GREEN, YELLOW, BLUE, CYAN, MAGENTA** - Color codes
- **BOLD, DIM** - Text formatting
- **RESET/NC** - Reset formatting
- Used in validation.sh for test results display
- Used in logging functions for colored output
- Referenced in user-facing messages (e.g., "run: ${CYAN}reload${RESET}")

## Usage Patterns

### Primary Users
1. **install.sh** - Uses most core functions for installation workflow
2. **lib/packages.sh** - Heavy use of logging and package management functions
3. **scripts/validate-install.sh** - Uses logging but relies more on validation.sh

### Function Categories by Usage
1. **Logging** (log, info, success, warn, error) - ~65% of all usage
2. **System Operations** (safe_sudo, command_exists) - ~15% of usage
3. **File Operations** (backup, symlink) - ~10% of usage
4. **WSL Functions** - ~5% of usage
5. **Validation Functions** - ~5% of usage

## Unused or Rarely Used Functions
Based on the grep analysis, all functions defined in core.sh appear to be used at least once, indicating good code utilization.

## Key Insights

1. **Essential Functions**: The logging functions (log, warn, error, success) are the most critical and widely used

2. **WSL Integration**: WSL functions are properly isolated and only called when IS_WSL is true

3. **Safety Features**: Functions like safe_sudo, safe_symlink, and backup_file show a focus on non-destructive operations

4. **Modular Design**: Each script sources core.sh independently, ensuring functions are available when needed

5. **Validation Split**: While core.sh has basic validation functions, the validation.sh module extends these with more comprehensive testing

## Recommendations

1. The core.sh module is well-utilized with no obvious dead code
2. Logging functions could potentially be enhanced with log levels or output redirection
3. WSL functions are appropriately segregated and conditionally used
4. The separation between core.sh and validation.sh is clean and logical