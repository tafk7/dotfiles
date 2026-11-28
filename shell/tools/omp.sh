#!/bin/bash

# Oh My Pi: whatever `omp` is on PATH. Only a hint when there is none; omp
# updates itself (`omp update`, or `dotfiles upgrade omp`).

unset -f omp 2>/dev/null

if ! command -v omp >/dev/null 2>&1; then
    omp() {
        echo "Oh My Pi not found. Install with: ./setup.sh --omp" >&2
        return 1
    }
fi
