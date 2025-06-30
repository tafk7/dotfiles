#!/bin/bash

# Main Dotfiles Installation Script
# Usage: ./install.sh [--work] [--personal] [--force] [--help]
set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load core modules in dependency order
load_core_modules() {
    local core_modules=(
        "scripts/core/common.sh"
        "scripts/core/logging.sh"
        "scripts/core/environment.sh" 
        "scripts/core/cli.sh"
        "scripts/core/packages.sh"
        "scripts/core/files.sh"
        "scripts/core/validation.sh"
        "scripts/core/orchestration.sh"
    )
    
    for module in "${core_modules[@]}"; do
        local module_path="$SCRIPT_DIR/$module"
        if [[ -f "$module_path" ]]; then
            source "$module_path"
        else
            echo "ERROR: Core module not found: $module_path"
            exit 1
        fi
    done
}

# Load security and integration modules
load_integration_modules() {
    local integration_modules=(
        "scripts/security/core.sh"
        "scripts/security/ssh.sh"
    )
    
    for module in "${integration_modules[@]}"; do
        local module_path="$SCRIPT_DIR/$module"
        if [[ -f "$module_path" ]]; then
            source "$module_path"
        else
            error "Integration module not found: $module_path"
            exit 1
        fi
    done
}


# Main installation function
main() {
    # Load all required modules
    load_core_modules
    load_integration_modules
    
    # Initialize environment
    init_environment
    export_environment
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Show banner
    echo "🚀 Dotfiles Installation System"
    echo "================================"
    echo
    
    # Run the installation workflow
    run_installation
}

# Execute main function with all arguments
main "$@"