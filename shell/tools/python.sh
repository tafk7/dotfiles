#!/bin/bash
# Python — aliases and functions

# Virtual environment shortcuts (uv-aware)
if command -v uv >/dev/null 2>&1; then
    alias venv='uv venv .venv'
    alias pipreqs='uv pip install -r requirements.txt'
else
    alias venv='python3 -m venv .venv'
    alias pipreqs='pip install -r requirements.txt'
fi

# Core Python aliases
alias py='python3'
alias ipy='ipython'

# Testing
alias pytest='python -m pytest'
alias pyt='python -m pytest -v'

# Code quality (if installed)
command -v black >/dev/null 2>&1 && alias fmt='black .'
if command -v ruff >/dev/null 2>&1; then
    alias lint='ruff check .'
    alias lintf='ruff check . --fix'
fi

# Quick server
alias pyserver='python -m http.server'

# uv shortcuts
if command -v uv >/dev/null 2>&1; then
    alias uvs='uv sync'
    alias uvr='uv run'
    alias uvt='uv tool install'
    alias uva='uv add'
    alias uvpi='uv pip install'
fi

# Set Python version for current project
pyset() {
    if ! command -v pyenv >/dev/null 2>&1; then
        echo "Error: pyenv is not installed"
        return 1
    fi

    # Handle --default flag
    if [[ "$1" == "--default" ]]; then
        if [[ -z "$2" ]]; then
            echo "Usage: pyset --default <python-version>"
            echo "Example: pyset --default 3.11.9"
            echo ""
            echo "Available Python versions:"
            pyenv versions --bare
            return 1
        fi

        local version="$2"

        if ! pyenv versions --bare | grep -q "^${version}$"; then
            echo "Python ${version} is not installed."
            echo "Install it with: pyenv install ${version}"
            return 1
        fi

        pyenv global "$version"
        rm -f "$HOME/.config/dotfiles/default-python-version"

        echo ""
        echo "✓ Default Python version set to ${version}"
        echo "✓ python and python3 commands now available globally"
        echo ""
        echo "This version will be used everywhere unless overridden by:"
        echo "  - A project's .python-version file (pyenv local)"
        echo "  - A .envrc with 'layout pyenv <version>' (direnv)"
        return 0
    fi

    if [[ -z "$1" ]]; then
        echo "Usage: pyset <python-version>"
        echo "       pyset --default <python-version>"
        echo ""
        echo "Examples:"
        echo "  pyset 3.11.9              # Set Python version for current project"
        echo "  pyset --default 3.11.9    # Set global default Python version"
        echo ""
        echo "Available Python versions:"
        pyenv versions --bare
        return 1
    fi

    local version="$1"

    if ! pyenv versions --bare | grep -q "^${version}$"; then
        echo "Python ${version} is not installed."
        echo "Install it with: pyenv install ${version}"
        return 1
    fi

    echo "Setting Python version to ${version}..."
    pyenv local "$version"

    if [[ -f pyproject.toml ]] && command -v poetry >/dev/null 2>&1; then
        echo "Configuring Poetry to use Python ${version}..."
        poetry env use python

        echo ""
        echo "✓ Python version set to ${version}"
        echo "✓ Poetry configured to use this version"
        echo ""
        echo "Next: Run 'poetry install' to create/update the virtual environment"
    else
        if [[ -d .venv ]]; then
            echo "Removing existing .venv..."
            rm -rf .venv
        fi

        echo "Creating virtual environment..."
        if command -v uv >/dev/null 2>&1; then
            uv venv .venv --python "$(pyenv which python)"
        else
            python -m venv .venv
        fi

        echo ""
        echo "✓ Python version set to ${version}"
        echo "✓ Virtual environment created at .venv/"
        echo ""
        echo "Next steps:"
        echo "  1. Activate: vactivate (or: source .venv/bin/activate)"
        if command -v uv >/dev/null 2>&1; then
            if [[ -f requirements.txt ]]; then
                echo "  2. Install: uv pip install -r requirements.txt"
            else
                echo "  2. Install packages: uv pip install <package-name>"
            fi
        else
            if [[ -f requirements.txt ]]; then
                echo "  2. Install: pip install -r requirements.txt"
            else
                echo "  2. Install packages: pip install <package-name>"
            fi
        fi
        echo ""
        echo "Tip: Add 'layout pyenv ${version}' to .envrc for auto-activation with direnv."
    fi
}

# Show current Python and Poetry environment info
pyinfo() {
    echo "=== Python Environment Info ==="
    echo ""

    if command -v pyenv >/dev/null 2>&1; then
        echo "pyenv version:"
        pyenv version
        echo ""

        if [[ -f .python-version ]]; then
            echo "Project Python version (from .python-version):"
            cat .python-version
            echo ""
        fi
    else
        echo "pyenv: not installed"
        echo ""
    fi

    if command -v uv >/dev/null 2>&1; then
        echo "uv: $(uv --version 2>/dev/null)"
    else
        echo "uv: not installed"
    fi
    echo ""

    if command -v direnv >/dev/null 2>&1; then
        echo "direnv: $(direnv --version 2>/dev/null)"
        if [[ -f .envrc ]]; then
            echo "  .envrc found in current directory"
        fi
    else
        echo "direnv: not installed"
    fi
    echo ""

    echo "Active Python:"
    which python || echo "  python: not found (enforcing venv usage ✓)"
    python --version 2>/dev/null || echo "  No python in PATH (use venv)"
    echo ""

    if command -v poetry >/dev/null 2>&1; then
        echo "Poetry environment:"
        poetry env info 2>/dev/null || echo "  No Poetry environment (run 'poetry install')"
    else
        echo "poetry: not installed"
    fi

    echo ""
    if [[ -n "${VIRTUAL_ENV:-}" ]]; then
        echo "✓ Virtual environment active: $VIRTUAL_ENV"
    else
        echo "✗ No virtual environment active"
        if [[ -d .venv ]]; then
            echo "  (Found .venv/ - activate with: source .venv/bin/activate)"
        fi
    fi
}

# List all pyenv Python versions with helpful info
pylist() {
    if ! command -v pyenv >/dev/null 2>&1; then
        echo "Error: pyenv is not installed"
        return 1
    fi

    echo "=== Installed Python Versions ==="
    pyenv versions
    echo ""
    echo "=== Available Versions (showing latest patches only) ==="
    pyenv install --list | grep -E '^\s*3\.(8|9|10|11|12|13)\.[0-9]+$' | tail -20
    echo ""
    echo "Install a version: pyenv install <version>"
    echo "Example: pyenv install 3.11.9"
}

# Universal venv activation
vactivate() {
    if [[ -d .venv ]]; then
        source .venv/bin/activate
        echo "✓ Virtual environment activated"

        if [[ -f pyproject.toml ]]; then
            echo "  (Poetry project)"
        elif [[ -f requirements.txt ]]; then
            echo "  (pip project)"
        fi
    else
        echo "No .venv found in current directory"

        if [[ -f pyproject.toml ]]; then
            echo "This is a Poetry project. Run: poetry install"
        elif [[ -f requirements.txt ]]; then
            echo "This is a pip project. Run: pyset <version>"
        else
            echo "Run 'pyset <version>' to create one"
        fi
        echo ""
        echo "Tip: Use 'layout pyenv <version>' in .envrc for auto-activation."
        return 1
    fi
}
