# Core.sh Version Comparison

## Size Comparison

| Version | Lines | File Size | Functions |
|---------|-------|-----------|-----------|
| **Original** | 424 | ~12KB | 24 functions |
| **Arete** | 52 | ~1.5KB | 7 functions |
| **Pragmatic** | 147 | ~4KB | 15 functions |

## What Each Version Keeps/Removes

### Original (424 lines) - Kitchen Sink
✓ Everything including:
- 60-line WSL username detection (5 methods!)
- Timestamp-based backup directories
- NPM global setup
- SSH key import from Windows
- Disk space validation
- Bash version checking
- Duplicate functions (log/info)
- Complex validation framework

### Arete (52 lines) - Minimal Purity
✓ Keeps:
- error() and success() only
- Basic WSL detection
- Git config setup
- Simple symlink function
- Basic validation

✗ Removes:
- log(), warn(), info() (100+ calls!)
- safe_sudo (10+ calls)
- All backup functionality
- WSL features
- Color variables
- Environment detection

### Pragmatic (147 lines) - Essential Functions
✓ Keeps:
- **All logging functions** (log, success, warn, error, wsl_log) - Required by 100+ calls
- **Essential helpers** (command_exists, is_wsl) - Used throughout
- **Safety wrappers** (safe_sudo, safe_symlink) - Non-destructive operations
- **Core features** (git config, WSL clipboard, basic validation)
- **Simple backups** (.bak files with timestamp)

✗ Removes:
- **WSL username complexity** (60 lines → 3 lines)
- **NPM setup** (belongs in packages.sh)
- **SSH import** (separate concern)
- **Backup directories** (overkill for dotfiles)
- **Prerequisite checks** (disk space, bash version)
- **Duplicate functions** (info === log)
- **Complex validation** (simplified to basics)

## Key Improvements in Pragmatic Version

1. **WSL Username**: 60 lines → 3 lines (one reliable method)
2. **Backups**: Complex directories → Simple .bak.timestamp files
3. **Validation**: 78 lines → 20 lines (just check files exist)
4. **Environment Detection**: 20 lines → 10 lines
5. **No Global State**: Removed complex backup prefix management

## Function Mapping

| Original Function | Pragmatic | Arete | Note |
|-------------------|-----------|--------|------|
| log() | ✓ | ✗ | 47 calls |
| warn() | ✓ | ✗ | 31 calls |
| error() | ✓ | ✓ | 28 calls |
| success() | ✓ | ✓ | 26 calls |
| info() | → log() | ✗ | Duplicate removed |
| safe_sudo() | ✓ | ✗ | 10+ calls |
| safe_symlink() | ✓ | → link_configs() | Simplified |
| command_exists() | ✓ | ✗ | Used everywhere |
| get_windows_username() | ✓ (3 lines) | ✓ | 60 → 3 lines |
| create_backup_dir() | → backup_file() | ✗ | Simplified |
| setup_npm_global() | ✗ | ✗ | Move to packages.sh |
| import_windows_ssh_keys() | ✗ | ✗ | Separate script |

## Migration Path

### To Pragmatic Version
- **No breaking changes** for logging functions
- Update `info()` calls to `log()` (simple find/replace)
- Remove backup directory parameter from function calls
- Move NPM setup to packages.sh
- Create separate WSL SSH import script if needed

### To Arete Version
- Rewrite 100+ logging calls
- Remove all safety features
- Lose backup functionality
- Break WSL integration
- Major refactoring required

## Recommendation

The **Pragmatic version** achieves the best balance:
- 65% code reduction from original
- Keeps all essential, heavily-used functions
- No breaking changes for most calls
- Removes actual complexity (WSL username detection)
- Maintains safety features
- Clear, simple, maintainable

This follows the Arete principle of "simplicity is divine" while respecting the pragmatic reality of the codebase.