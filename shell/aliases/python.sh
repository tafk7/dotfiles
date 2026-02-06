#!/bin/bash
# Python development aliases

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
if command -v black >/dev/null 2>&1; then
    alias fmt='black .'
fi
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
