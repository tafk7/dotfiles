#!/bin/bash
# Installation verification - checks for real issues and installation status

echo "=== Dotfiles Setup Verification ==="
echo

# Track if we found any issues
issues_found=0

# 1. Check critical symlinks
echo "Checking configuration files..."
# Note: .gitconfig is a template, not a symlink
symlink_configs=(~/.bashrc ~/.zshrc ~/.tmux.conf)
for config in "${symlink_configs[@]}"; do
    if [[ ! -e "$config" ]]; then
        echo "❌ Missing: $config"
        issues_found=1
    elif [[ -L "$config" ]]; then
        echo "✅ Linked: $config"
    else
        echo "⚠️  Not a symlink: $config (may be overwritten on next install)"
    fi
done

# Check gitconfig separately (it's a processed template, not a symlink)
if [[ -f ~/.gitconfig ]]; then
    echo "✅ Present: ~/.gitconfig (processed template)"
else
    echo "❌ Missing: ~/.gitconfig"
    issues_found=1
fi
echo

# 2. Docker group membership (silent permission failures)
if command -v docker >/dev/null 2>&1; then
    # Check /etc/group for membership
    if grep "^docker:" /etc/group | grep -q "\b$USER\b"; then
        # In group file, check if active in current session
        if groups | grep -q docker; then
            echo "✅ Docker group membership active"
        else
            echo "ℹ️  Docker group added (log out and back in to activate)"
        fi
    else
        echo "❌ Not in docker group"
        echo "   Fix: sudo usermod -aG docker $USER"
        issues_found=1
    fi
fi

# 3. Git config template placeholders (would break git mysteriously)
if [[ -f ~/.gitconfig ]]; then
    if grep -q "{{GIT_" ~/.gitconfig 2>/dev/null; then
        echo "❌ Git config has template placeholders - rerun installer"
        issues_found=1
    else
        # Check if git is actually configured
        git_name=$(git config --get user.name 2>/dev/null)
        git_email=$(git config --get user.email 2>/dev/null)
        if [[ -z "$git_name" || -z "$git_email" ]]; then
            echo "⚠️  Git user not configured"
            echo "   Fix: git config --global user.name \"Your Name\""
            echo "        git config --global user.email \"your@email.com\""
        else
            echo "✅ Git configured as: $git_name <$git_email>"
        fi
    fi
fi

# 4. NVM and Node.js setup
if [[ -d "$HOME/.nvm" ]] && [[ -s "$HOME/.nvm/nvm.sh" ]]; then
    # Source NVM to check if it works
    export NVM_DIR="$HOME/.nvm"
    if . "$NVM_DIR/nvm.sh" 2>/dev/null && command -v nvm >/dev/null 2>&1; then
        echo "✅ NVM is installed and functional"
        if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
            echo "✅ Node.js $(node --version) and npm $(npm --version) available via NVM"
        else
            echo "⚠️  NVM is installed but Node.js is not"
            echo "   Fix: nvm install --lts"
        fi
    else
        echo "⚠️  NVM directory exists but NVM is not functional"
        echo "   Fix: Reinstall with ./scripts/install-nvm.sh"
    fi
elif command -v node >/dev/null 2>&1; then
    # Node installed but not via NVM
    echo "⚠️  Node.js is installed but not via NVM"
    echo "   This may cause permission issues with global packages"
    echo "   Fix: Install NVM with ./scripts/install-nvm.sh"
fi

# 5. WSL-specific checks
if grep -qi microsoft /proc/version 2>/dev/null; then
    echo
    echo "WSL-specific checks..."
    
    # Clipboard scripts
    if [[ -f ~/.local/bin/pbcopy ]]; then
        if [[ ! -x ~/.local/bin/pbcopy ]]; then
            chmod +x ~/.local/bin/pbcopy ~/.local/bin/pbpaste 2>/dev/null
            echo "✅ Fixed clipboard script permissions"
        else
            echo "✅ WSL clipboard integration present"
        fi
    else
        echo "⚠️  WSL clipboard scripts not installed"
    fi
fi

# 6. Shell integration
echo
echo "Checking shell integration..."
if [[ -f ~/.bashrc ]] && grep -q "scripts/aliases" ~/.bashrc; then
    echo "✅ Bash aliases integrated"
else
    echo "❌ Bash aliases not integrated - source ~/.bashrc"
    issues_found=1
fi

# 7. Essential commands
echo
echo "Checking essential tools..."
essential_tools=(git curl wget)
for tool in "${essential_tools[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "✅ $tool available"
    else
        echo "❌ $tool missing - install with: sudo apt-get install $tool"
        issues_found=1
    fi
done

# Summary
echo
if [[ $issues_found -eq 0 ]]; then
    echo "✅ All checks passed! Your dotfiles are properly installed."
else
    echo "⚠️  Some issues were found - see above for fixes."
fi
echo
echo "To reload your configuration: source ~/.bashrc"

# Exit with the number of issues found
exit $issues_found