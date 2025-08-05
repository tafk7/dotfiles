#!/bin/bash
# Installation verification - checks for real issues and installation status

echo "=== Dotfiles Setup Verification ==="
echo

# Track if we found any issues
issues_found=0

# 1. Check critical symlinks
echo "Checking configuration files..."
critical_configs=(~/.bashrc ~/.zshrc ~/.gitconfig)
for config in "${critical_configs[@]}"; do
    if [[ ! -e "$config" ]]; then
        echo "❌ Missing: $config"
        issues_found=1
    elif [[ -L "$config" ]]; then
        echo "✅ Linked: $config"
    else
        echo "⚠️  Not a symlink: $config (may be overwritten on next install)"
    fi
done
echo

# 2. Docker group membership (silent permission failures)
if command -v docker >/dev/null 2>&1; then
    if ! groups | grep -q docker; then
        echo "⚠️  Docker installed but you're not in docker group"
        echo "   Fix: sudo usermod -aG docker $USER && newgrp docker"
        issues_found=1
    else
        echo "✅ Docker group membership OK"
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

# 4. NPM prefix (prevents future EACCES permission errors)
if command -v npm >/dev/null 2>&1; then
    prefix=$(npm config get prefix 2>/dev/null)
    if [[ "$prefix" == "$HOME/.npm-global" ]]; then
        echo "✅ NPM prefix correctly set to ~/.npm-global"
    elif [[ "$prefix" == "/usr"* ]]; then
        echo "✅ NPM using system prefix: $prefix"
    else
        echo "⚠️  NPM prefix is $prefix"
        echo "   This may cause permission issues when installing global packages"
        echo "   Fix: npm config set prefix ~/.npm-global"
    fi
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