#!/bin/bash
# Python — aliases and functions

# Virtual environment shortcuts (uv-aware)
if command -v uv >/dev/null 2>&1; then
    alias venv='uv venv .venv'                          # Create .venv (with uv when it is installed)
    alias pipreqs='uv pip install -r requirements.txt'  # Install from requirements.txt (with uv when it is installed)
else
    alias venv='python3 -m venv .venv'
    alias pipreqs='pip install -r requirements.txt'
fi

# Core Python aliases
alias py='python3'   # Python 3 interpreter
alias ipy='ipython'  # IPython interpreter

# Testing
alias pytest='python3 -m pytest'  # Run tests
alias pyt='python3 -m pytest -v'  # Run tests with verbose output

# Resolve optional tools on invocation. A missing-tool PATH search can traverse
# Windows mounts on WSL; it should not delay every new shell.
fmt() { command black . "$@"; }  # Format code with black
lint() { command ruff check . "$@"; }  # Check code with ruff
lintf() { command ruff check . --fix "$@"; }  # Auto-fix ruff issues

# Quick server
alias pyserver='python3 -m http.server'  # Start HTTP server in current directory

# uv shortcuts — uv owns interpreters, venvs, deps, and tools.
# Native commands cover the rest: `uv python list/install/pin`, `uv venv`.
if command -v uv >/dev/null 2>&1; then
    alias uvs='uv sync'          # Sync project dependencies
    alias uvr='uv run'           # Run command in project environment
    alias uvt='uv tool install'  # Install CLI tool globally
    alias uva='uv add'           # Add dependency to project
    alias uvpi='uv pip install'  # Install package with uv pip
fi

# Activate the project virtualenv (.venv). Tool-agnostic convenience;
# with uv you can also skip activation entirely via `uv run`.
vactivate() {
    if [[ -d .venv ]]; then
        # shellcheck source=/dev/null
        source .venv/bin/activate
        echo "✓ Virtual environment activated"
    else
        echo "No .venv found in current directory."
        if [[ -f pyproject.toml ]]; then
            echo "uv project detected — run 'uv sync' to create the environment."
        elif [[ -f requirements.txt ]]; then
            echo "Create one with: uv venv && uv pip install -r requirements.txt"
        else
            echo "Create one with: uv venv  (optionally: uv venv --python <version>)"
        fi
        return 1
    fi
}
