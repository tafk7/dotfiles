# WSL Enhancements Documentation

This document describes the enhanced WSL (Windows Subsystem for Linux) integration features added to the dotfiles system.

## Overview

The WSL enhancements provide seamless integration between Linux and Windows environments, including:
- GUI application support (X11/WSLg)
- Windows Terminal integration
- Advanced path conversion utilities
- Cross-filesystem performance optimizations

## Features

### 1. GUI Application Support (`scripts/wsl/gui_setup.sh`)

Enables running Linux GUI applications on Windows with automatic configuration for:

#### WSLg (WSL2)
- Automatic detection and configuration
- Native Wayland and X11 support
- Audio passthrough via PulseAudio
- Hardware acceleration when available

#### X11 Forwarding (WSL1/Fallback)
- Automatic DISPLAY configuration
- Windows host IP detection
- X server integration (VcXsrv, X410)

#### Features:
- **Auto-detection**: Detects WSL version and configures accordingly
- **Prerequisites**: Installs required packages (X11, GTK, Qt, Mesa)
- **Environment**: Sets up all necessary environment variables
- **Testing**: Includes GUI verification tools

#### Usage:
```bash
# Run during installation (automatic)
./install.sh

# Or run manually
./scripts/wsl/gui_setup.sh

# Test GUI
xclock  # Simple test
glxinfo | grep "direct rendering"  # Check hardware acceleration

# Launch GUI apps
wsl-gui-launch firefox
wsl-gui-launch code
```

### 2. Windows Terminal Integration (`scripts/wsl/terminal_integration.sh`)

Deep integration with Windows Terminal including:

#### Terminal Profile Generation
- Custom WSL profiles with Gruvbox theme
- Cascadia Code font configuration
- Transparency and acrylic effects
- Custom icons per distribution

#### Shell Functions
- `wt` - Open Windows Terminal in current directory
- `wt-tab` - Open new tab
- `wt-pane` - Split pane (vertical/horizontal)  
- `wt-settings` - Open settings
- `set-tab-title` - Set tab title
- `set-tab-color` - Set tab color
- `notify-windows` - Send Windows notifications

#### PowerShell Integration
- `Start-WSL.ps1` - Enhanced WSL launcher
- `Convert-WSLPath.ps1` - Path conversion utility
- `Start-WSLApp.ps1` - GUI app launcher

#### Usage:
```bash
# Shell functions (after sourcing ~/.wsl_terminal_functions)
wt                    # Open new Terminal window
wt-tab                # New tab in current window
wt-pane vertical      # Split vertically
set-tab-title "Dev"   # Set tab title
set-tab-color green   # Set tab color
notify-windows "Build Complete" "Your build has finished"

# PowerShell (from Windows)
Start-WSL -Distribution Ubuntu -Command "htop"
Convert-WSLPath -Path "/home/user" -ToWindows
Start-WSLApp -Application firefox
```

### 3. Path Utilities (`scripts/wsl/path_utils.sh`)

Advanced path conversion and manipulation:

#### Conversion Functions
- `wsl_to_windows` - Convert WSL paths to Windows format
- `windows_to_wsl` - Convert Windows paths to WSL format
- `unc_to_wsl` - Handle UNC network paths
- `smart_path_convert` - Auto-detect and convert paths

#### Batch Operations
- Convert entire files of paths
- Handle mixed path formats
- Performance optimized with caching

#### Clipboard Integration
- `cpwd` - Copy current directory as Windows path
- `cpwdl` - Copy as WSL path
- `cpwdu` - Copy as UNC path

#### Git Integration
- Automatic path handling in git commands
- Windows editor integration
- Cross-filesystem optimization

#### Usage:
```bash
# Quick conversions
wp /home/user          # → C:\Users\...\Ubuntu\home\user
lp "C:\Windows"        # → /mnt/c/Windows
cpath \\server\share   # → /mnt/server/share

# Clipboard operations
cpwd                   # Copy pwd as Windows path
copy_path . unc        # Copy as UNC path

# Navigation
cdw "C:\Projects"      # cd to Windows path
exp .                  # Open current dir in Explorer

# Batch conversion
ls -1 | paths2win      # Convert list to Windows paths
find . -type f | paths2wsl > wsl_paths.txt

# Path information
pathinfo /mnt/c/Users  # Show all path formats
```

## Installation

The WSL enhancements are automatically installed when running the main installer in a WSL environment:

```bash
./install.sh
```

To install only WSL enhancements:
```bash
./scripts/wsl/gui_setup.sh
./scripts/wsl/terminal_integration.sh  
./scripts/wsl/path_utils.sh
```

## Requirements

### For GUI Support:
- **WSL2 + WSLg**: Windows 11 or Windows 10 Build 19044+
- **WSL1/WSL2 without WSLg**: X server on Windows (VcXsrv, X410, Xming)

### For Terminal Integration:
- Windows Terminal (from Microsoft Store)
- PowerShell 5.1 or later

### For Path Utilities:
- WSL1 or WSL2
- `wslpath` command (included in recent WSL)

## Performance Tips

1. **Keep code in Linux filesystem** (`/home`) for best performance
2. **Use Windows filesystem** (`/mnt/c`) only for Windows interop
3. **Exclude WSL paths from Windows Defender**:
   ```powershell
   # Run as Administrator in PowerShell
   Add-MpPreference -ExclusionPath "\\wsl$\Ubuntu"
   ```

4. **For large file operations**, use Linux filesystem or rsync

## Troubleshooting

### GUI Applications Not Displaying

1. **Check DISPLAY variable**:
   ```bash
   echo $DISPLAY  # Should show :0 or similar
   ```

2. **For WSL1/non-WSLg**:
   - Ensure X server is running on Windows
   - Check Windows Firewall settings
   - Try: `export DISPLAY=$(ip route | grep default | awk '{print $3}'):0`

3. **Test with simple app**:
   ```bash
   xclock  # Should show a clock
   ```

### Windows Terminal Issues

1. **Profile not showing**:
   - Manually add profile from `~/.wsl_terminal_settings.json`
   - Restart Windows Terminal

2. **Functions not working**:
   - Source the functions: `source ~/.wsl_terminal_functions`
   - Check if `wt.exe` is in PATH

### Path Conversion Issues

1. **Invalid paths**:
   - Ensure path exists before conversion
   - Use quotes for paths with spaces
   - Check permissions

2. **Performance**:
   - Path cache is cleared on new sessions
   - For bulk operations, use batch conversion functions

## Advanced Configuration

### Custom X11 Settings

Edit `~/.wsl_gui_env` to customize:
```bash
export GDK_SCALE=2              # HiDPI scaling
export QT_SCALE_FACTOR=1.5      # Qt app scaling
export MESA_GL_VERSION_OVERRIDE=4.5  # OpenGL version
```

### Terminal Color Schemes

Additional schemes can be added to Windows Terminal settings:
```json
{
    "schemes": [
        {
            "name": "Custom WSL Theme",
            "background": "#1e1e1e",
            "foreground": "#cccccc",
            // ... more colors
        }
    ]
}
```

### Path Aliases

Create custom path aliases in `~/.wsl_path_aliases`:
```bash
alias proj='cdw "C:\Projects"'
alias dl='cdw "$WIN_DOWNLOADS"'
```

## Security Considerations

1. **X11 Security**: WSLg provides better isolation than traditional X11 forwarding
2. **Path Validation**: All path conversions validate input
3. **PowerShell Scripts**: Execution policy may need adjustment:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

## Future Enhancements

Planned improvements:
- Docker Desktop integration
- VS Code Server optimization
- Network drive mapping
- Systemd support (when available)
- GPU compute support