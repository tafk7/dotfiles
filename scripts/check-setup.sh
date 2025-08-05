#!/bin/bash
# Minimal validation - only non-obvious issues that would confuse users

echo "Checking for common setup issues..."

# Docker group membership (silent permission failures)
if command -v docker >/dev/null && ! groups | grep -q docker; then
    echo "⚠️  Not in docker group - run: sudo usermod -aG docker \$USER && newgrp docker"
fi

# Git config template placeholders (would break git mysteriously)
if grep -q "{{GIT_" ~/.gitconfig 2>/dev/null; then
    echo "❌ Git config has template placeholders - rerun installer"
fi

# NPM prefix (prevents future EACCES permission errors)
if command -v npm >/dev/null; then
    prefix=$(npm config get prefix 2>/dev/null)
    if [[ "$prefix" != "$HOME/.npm-global" && "$prefix" != "/usr"* ]]; then
        echo "⚠️  NPM prefix is $prefix - may cause permission issues"
    fi
fi

# WSL clipboard executability (fails silently)
if [[ -f ~/.local/bin/pbcopy && ! -x ~/.local/bin/pbcopy ]]; then
    chmod +x ~/.local/bin/pbcopy ~/.local/bin/pbpaste 2>/dev/null
    echo "✅ Fixed clipboard script permissions"
fi

echo "Check complete!"