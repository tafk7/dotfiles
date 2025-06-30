# Dotfiles Alias Cheat Sheet

> **Security Update:** Some aliases have been changed for system safety. See [Security Features](#security-features) section for details.

## Navigation & Files

| Alias | Command | When to Use |
|-------|---------|-------------|
| `..` | `cd ..` | Go up one directory |
| `...` | `cd ../..` | Go up two directories |
| `....` | `cd ../../..` | Go up three directories |
| `~` | `cd ~` | Go to home directory |
| `-` | `cd -` | Go to previous directory |
| `ls` | `eza --icons` | List files with icons |
| `ll` | `eza -alF --icons` | Detailed list with hidden files |
| `la` | `eza -A --icons` | List all except . and .. |
| `l` | `eza -CF --icons` | Compact multi-column list |
| `tree` | `eza --tree --icons` | Show directory tree |
| `c` | `bat` or `batcat` | View file with syntax highlighting |
| `view` | `bat` or `batcat` | Alternative syntax highlighting viewer |
| `f` | `fd` or `fdfind` | Fast file search |

## System & Process

| Alias | Command | When to Use |
|-------|---------|-------------|
| `df` | `df -h` | Check disk space (human readable) |
| `du` | `du -h` | Check directory sizes |
| `du1` | `du -h --max-depth=1` | Size of current directory contents |
| `free` | `free -h` | Check memory usage |
| `ps` | `ps auxf` | Show all processes with tree |
| `psg <name>` | Process search function | Find processes by name (try: `psg chrome`) |
| `psmem` | Sort processes by memory | Find memory hogs |
| `pscpu` | Sort processes by CPU | Find CPU hogs |
| `htop` | Better process viewer | Monitor system resources |

## Network

| Alias | Command | When to Use |
|-------|---------|-------------|
| `myip` | `curl ifconfig.me` | Get public IP address |
| `localip` | `hostname -I` | Get local IP address |
| `ping` | `ping -c 5` | Ping with 5 packets only |
| `ports` | `netstat -tulanp` | Show open ports |

## Shell & Config

| Alias | Command | When to Use |
|-------|---------|-------------|
| `reload` | `source ~/.zshrc` | Apply config changes |
| `zshrc` | `vim ~/.zshrc` | Edit shell config |
| `h` | `history` | Show command history |
| `hgrep <term>` | `history \| grep` | Search command history |

## Tmux

### Session Management Aliases

| Alias | Command | When to Use |
|-------|---------|-------------|
| `tm <name>` | `tmux new -s` | Create new named session |
| `ta <name>` | `tmux attach -t` | Attach to existing session |
| `tl` | `tmux list-sessions` | List all sessions |
| `tk <name>` | `tmux kill-session -t` | Kill specific session |

### Tmux Key Bindings (Prefix: Ctrl+a)

| Action | Keys | Description |
|--------|------|-------------|
| **Navigation** |
| `Alt + ←/→/↑/↓` | Direct | Switch panes without prefix |
| `Ctrl+a` → `←/→/↑/↓` | With prefix | Navigate to pane |
| **Resizing** |
| `Ctrl+a` → `Shift+←` | Resize left | Shrink pane by 5 |
| `Ctrl+a` → `Shift+→` | Resize right | Expand pane by 5 |
| `Ctrl+a` → `Shift+↑` | Resize up | Shrink pane by 5 |
| `Ctrl+a` → `Shift+↓` | Resize down | Expand pane by 5 |
| **Splitting** |
| `Ctrl+a` → `\|` | Split vertical | Create vertical split |
| `Ctrl+a` → `-` | Split horizontal | Create horizontal split |
| **Other** |
| `Ctrl+a` → `r` | Reload config | Apply config changes |
| `Ctrl+a` → `c` | New window | Create new window |
| `Ctrl+a` → `,` | Rename window | Name current window |

## Git Essentials

| Alias | Command | When to Use |
|-------|---------|-------------|
| `g` | `git` | Git shorthand |
| **Status/Diff** |
| `gs` | `git status -sb` | Quick status summary |
| `gd` | `git diff` | Show unstaged changes |
| `gdc` | `git diff --cached` | Show staged changes |
| **Staging** |
| `ga <file>` | `git add` | Stage specific files |
| `gaa` | `git add .` | Stage all changes |
| **Commits** |
| `gc` | `git commit` | Commit with editor |
| `gcm "msg"` | `git commit -m` | Commit with message |
| `gca` | `git commit --amend` | Amend last commit |
| **Branches** |
| `gb` | `git branch` | List branches |
| `gco <branch>` | `git checkout` | Switch branches |
| `gcb <name>` | `git checkout -b` | Create & switch branch |
| **Remote** |
| `gp` | `git push` | Push to remote |
| `gpl` | `git pull` | Pull from remote |
| `gpu` | `git push -u origin HEAD` | Push new branch |
| **History** |
| `gl` | `git log --graph` | View commit graph |
| `gla` | `git log --all --graph` | Graph of all branches |
| **Stash** |
| `gst` | `git stash` | Stash changes |
| `gstp` | `git stash pop` | Apply & remove stash |

### Git Functions

> **Note**: Advanced git functions are available but not yet implemented in this version.

## Docker

| Alias | Command | When to Use |
|-------|---------|-------------|
| **Containers** |
| `dps` | `docker ps` | List running containers |
| `dpsa` | `docker ps -a` | List all containers |
| `dexec <id>` | `docker exec -it` | Execute command in container |
| `dlogs <id>` | `docker logs -f` | Follow container logs |
| `dstop <id>` | `docker stop` | Stop container gracefully |
| `drm <id>` | `docker rm` | Remove stopped container |
| `drmf <id>` | `docker rm -f` | Force remove container |
| **Images** |
| `di` | `docker images` | List images |
| `dpull <image>` | `docker pull` | Download image |
| `dbuild <tag> .` | `docker build -t` | Build image with tag |
| `drmi <id>` | `docker rmi` | Remove image |
| **Compose** |
| `dc` | `docker compose` | Docker compose shorthand |
| `dcu` | `docker compose up -d` | Start services detached |
| `dcd` | `docker compose down` | Stop and remove services |
| `dcl` | `docker compose logs -f` | Follow compose logs |
| `dcr` | `docker compose restart` | Restart services |
| `dcb` | `docker compose build` | Build compose images |
| **Cleanup** |
| `dprune` | `docker system prune -f` | Remove unused data |
| `dprunea` | `docker system prune -af` | Remove all unused data |

### Docker Functions

> **Note**: Advanced docker functions are available but not yet implemented in this version.

## WSL Specific

### Windows Navigation

> **Note**: Advanced Windows navigation aliases are planned for future implementation.

### Windows Integration

| Alias | Command | When to Use |
|-------|---------|-------------|
| `open` | `explorer.exe` | Open files/folders in Windows |
| `e` | `explorer.exe .` | Open current dir in Explorer |
| `notepad` | `notepad.exe` | Quick edit with Notepad |
| `pwsh` | `powershell.exe` | Launch PowerShell |
| `cmd` | `cmd.exe` | Launch Command Prompt |

### Clipboard Operations

| Alias | Command | When to Use |
|-------|---------|-------------|
| `pbcopy` | `clip.exe` | Copy to Windows clipboard |
| `pbpaste` | Get Windows clipboard | Paste from Windows clipboard |
| `cwd` | Copy pwd to clipboard | Share current path with Windows |

### Path Conversion

| Alias | Command | When to Use |
|-------|---------|-------------|
| `wpath <path>` | Convert to Windows path | Get `C:\` style path |
| `lpath <path>` | Convert to Linux path | Get `/mnt/c/` style path |

### SSH Management

| Alias | Command | When to Use |
|-------|---------|-------------|
| `win-ssh` | List Windows SSH keys | See available SSH keys |
| `sync-ssh` | Copy Windows SSH keys | Import keys to WSL |

### WSL Functions

> **Note**: Advanced WSL integration functions are planned for future implementation.

### Practical WSL Examples

```bash
# Copy file to Windows Desktop
cp report.pdf $WIN_DESKTOP/

# Open current project in Windows Explorer
cd ~/projects/myapp && e

# Copy command output to Windows clipboard
ls -la | pbcopy

# Convert paths for scripts
docker run -v "$(wpath .)":/app myimage

# Quick share: copy file path for Windows
wpath ./config.json | pbcopy
```

## Archive Operations

> **Note**: Specialized archive aliases are available through standard tar commands. Use `tar --help` for options.

## Alias Safety

For system stability, some traditional command overrides have been implemented as new aliases:

| Original Command | Safe Alias | Purpose |
|-----------------|------------|---------|
| `find` | `f` | Preserves system `find` for scripts |
| `cat` | `c` / `view` | Preserves standard `cat` output |
| `grep` | (uses ripgrep) | Much faster searching |

### Access Original Commands

If you need the original commands:

```bash
\cat file.txt             # Bypass alias
command cat file.txt      # Alternative method
```


## Quick Tips

- **Tab completion** works with most aliases
- **Combine aliases**: `gaa && gcm "update" && gp`
- **Check what an alias does**: `type <alias>`
- **List all aliases**: `alias`
- **Use original commands**: `\command` or `command command`
- **Process search help**: Run `psg` without arguments for usage
- **Archive operations**: Use `tarc` to create, `tarx` to extract, `untar` for .gz files