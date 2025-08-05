#!/bin/bash
# Python development aliases - essentials only

# Virtual environment shortcuts
alias venv='python3 -m venv venv'
alias activate='source venv/bin/activate'
alias pipreqs='pip install -r requirements.txt'

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