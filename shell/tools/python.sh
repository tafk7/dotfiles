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

# uv shortcuts — uv owns interpreters, venvs, deps, and tools.
# Native commands cover the rest: `uv python list/install/pin`, `uv venv`.
if command -v uv >/dev/null 2>&1; then
    alias uvs='uv sync'
    alias uvr='uv run'
    alias uvt='uv tool install'
    alias uva='uv add'
    alias uvpi='uv pip install'
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
