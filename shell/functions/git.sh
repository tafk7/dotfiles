#!/bin/bash
# Git functions (extracted from shell/aliases/git.sh)

# Undo last commit but keep changes
gundo() {
    git reset HEAD~1 --soft
}
