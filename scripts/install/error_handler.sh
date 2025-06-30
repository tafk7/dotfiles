#!/bin/bash

# Unified Error Handling System for Dotfiles Installation
# Provides centralized error handling, cleanup, and recovery

# Error handling configuration
declare -g ERROR_LOG="${ERROR_LOG:-$HOME/.dotfiles_error.log}"
declare -g ERROR_COUNT=0
declare -g LAST_ERROR=""
declare -g -a ERROR_HANDLERS=()
declare -g -a CLEANUP_FUNCTIONS=()
declare -g EXIT_ON_ERROR="${EXIT_ON_ERROR:-true}"

# Source transaction management if available
if [[ -f "${BASH_SOURCE%/*}/transaction.sh" ]]; then
    source "${BASH_SOURCE%/*}/transaction.sh"
fi

# Setup error handlers for the current script
setup_error_handlers() {
    local script_name="${1:-$(basename "$0")}"
    
    # Enable strict error handling
    set -eE
    set -o pipefail
    set -u
    
    # Set up error trap
    trap 'handle_error "$script_name" "$LINENO" "$?" "$BASH_COMMAND"' ERR
    
    # Set up exit trap for cleanup
    trap 'cleanup_on_exit' EXIT
    
    # Set up signal traps
    trap 'handle_interrupt' INT TERM
    
    log "Error handlers configured for: $script_name"
}

# Main error handler
handle_error() {
    local script_name="${1:-unknown}"
    local line_number="${2:-0}"
    local exit_code="${3:-1}"
    local failed_command="${4:-unknown command}"
    
    # Increment error count
    ((ERROR_COUNT++))
    LAST_ERROR="$failed_command at $script_name:$line_number"
    
    # Log error details
    {
        echo "=== ERROR ==="
        echo "Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "Script: $script_name"
        echo "Line: $line_number"
        echo "Exit Code: $exit_code"
        echo "Command: $failed_command"
        echo "Working Directory: $(pwd)"
        echo "User: $USER"
        echo ""
        echo "Stack Trace:"
        local frame=0
        while caller $frame; do
            ((frame++))
        done
        echo ""
    } | tee -a "$ERROR_LOG" >&2
    
    # Display user-friendly error message
    error "Installation failed at $script_name:$line_number"
    error "Command: $failed_command"
    error "Exit code: $exit_code"
    
    # Run custom error handlers
    run_error_handlers "$script_name" "$line_number" "$exit_code" "$failed_command"
    
    # Perform cleanup
    if [[ "$EXIT_ON_ERROR" == true ]]; then
        error "Running cleanup procedures..."
        cleanup_on_error
        
        # Rollback transaction if active
        if [[ "$TRANSACTION_ACTIVE" == true ]]; then
            rollback_transaction "Error in $script_name at line $line_number"
        fi
        
        # Update installation state
        if command -v save_state >/dev/null 2>&1; then
            save_state "failed"
        fi
        
        error "Installation failed. Check $ERROR_LOG for details."
        exit "$exit_code"
    else
        warn "Error occurred but continuing (EXIT_ON_ERROR=false)"
    fi
}

# Handle interruption signals
handle_interrupt() {
    echo ""
    error "Installation interrupted by user"
    
    # Log interruption
    {
        echo "=== INTERRUPTED ==="
        echo "Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "Signal: $1"
        echo ""
    } >> "$ERROR_LOG"
    
    # Perform cleanup
    cleanup_on_error
    
    # Rollback transaction if active
    if [[ "$TRANSACTION_ACTIVE" == true ]]; then
        rollback_transaction "User interrupted installation"
    fi
    
    # Update state
    if command -v save_state >/dev/null 2>&1; then
        save_state "interrupted"
    fi
    
    exit 130
}

# Register a custom error handler
register_error_handler() {
    local handler_function="$1"
    local description="${2:-Custom error handler}"
    
    if declare -f "$handler_function" >/dev/null; then
        ERROR_HANDLERS+=("$handler_function")
        log "Registered error handler: $description"
    else
        warn "Error handler function not found: $handler_function"
    fi
}

# Register a cleanup function
register_cleanup_function() {
    local cleanup_function="$1"
    local description="${2:-Cleanup function}"
    
    if declare -f "$cleanup_function" >/dev/null; then
        CLEANUP_FUNCTIONS+=("$cleanup_function")
        log "Registered cleanup function: $description"
    else
        warn "Cleanup function not found: $cleanup_function"
    fi
}

# Run all registered error handlers
run_error_handlers() {
    local script_name="$1"
    local line_number="$2"
    local exit_code="$3"
    local failed_command="$4"
    
    for handler in "${ERROR_HANDLERS[@]}"; do
        if declare -f "$handler" >/dev/null; then
            log "Running error handler: $handler"
            "$handler" "$script_name" "$line_number" "$exit_code" "$failed_command" || true
        fi
    done
}

# Cleanup on error
cleanup_on_error() {
    log "Performing error cleanup..."
    
    # Run registered cleanup functions
    for cleanup_func in "${CLEANUP_FUNCTIONS[@]}"; do
        if declare -f "$cleanup_func" >/dev/null; then
            log "Running cleanup: $cleanup_func"
            "$cleanup_func" || true
        fi
    done
    
    # Remove temporary files
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        log "Removing temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
    
    # Kill background processes
    local jobs_count
    jobs_count=$(jobs -p | wc -l)
    if [[ $jobs_count -gt 0 ]]; then
        log "Terminating $jobs_count background processes"
        jobs -p | xargs -r kill 2>/dev/null || true
    fi
}

# Cleanup on normal exit
cleanup_on_exit() {
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        # Normal exit - minimal cleanup
        if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
            rm -rf "$TEMP_DIR"
        fi
    else
        # Error exit - full cleanup
        cleanup_on_error
    fi
}

# Safe command execution with error handling
safe_execute() {
    local description="$1"
    shift
    local command=("$@")
    
    log "Executing: $description"
    
    if "${command[@]}"; then
        success "$description completed"
        return 0
    else
        local exit_code=$?
        error "$description failed with exit code: $exit_code"
        return $exit_code
    fi
}

# Retry command with exponential backoff
retry_with_backoff() {
    local max_attempts="${1:-3}"
    local initial_delay="${2:-1}"
    local description="$3"
    shift 3
    local command=("$@")
    
    local attempt=1
    local delay=$initial_delay
    
    while [[ $attempt -le $max_attempts ]]; do
        log "Attempt $attempt/$max_attempts: $description"
        
        if "${command[@]}"; then
            success "$description succeeded on attempt $attempt"
            return 0
        else
            local exit_code=$?
            
            if [[ $attempt -lt $max_attempts ]]; then
                warn "$description failed (attempt $attempt), retrying in ${delay}s..."
                sleep "$delay"
                delay=$((delay * 2))  # Exponential backoff
            else
                error "$description failed after $max_attempts attempts"
                return $exit_code
            fi
        fi
        
        ((attempt++))
    done
}

# Check prerequisites before operations
check_prerequisites() {
    local -a missing_commands=()
    local -a failed_checks=()
    
    # Check required commands
    local required_commands=("curl" "git" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        error "Missing required commands: ${missing_commands[*]}"
        failed_checks+=("Missing commands: ${missing_commands[*]}")
    fi
    
    # Check disk space (require at least 1GB free)
    local free_space_mb
    free_space_mb=$(df -m "$HOME" | awk 'NR==2 {print $4}')
    if [[ $free_space_mb -lt 1024 ]]; then
        error "Insufficient disk space: ${free_space_mb}MB free (need at least 1GB)"
        failed_checks+=("Insufficient disk space")
    fi
    
    # Check internet connectivity
    if ! curl -s --head --connect-timeout 5 https://github.com >/dev/null; then
        warn "No internet connectivity detected"
        failed_checks+=("No internet connectivity")
    fi
    
    # Check sudo access (if needed)
    if [[ "${REQUIRE_SUDO:-true}" == true ]]; then
        if ! sudo -n true 2>/dev/null; then
            if ! sudo -v; then
                error "Sudo access required but not available"
                failed_checks+=("No sudo access")
            fi
        fi
    fi
    
    # Report results
    if [[ ${#failed_checks[@]} -gt 0 ]]; then
        error "Prerequisites check failed:"
        for check in "${failed_checks[@]}"; do
            error "  - $check"
        done
        return 1
    else
        success "All prerequisites satisfied"
        return 0
    fi
}

# Generate error report
generate_error_report() {
    local report_file="${1:-$HOME/dotfiles-error-report-$(date +%Y%m%d-%H%M%S).txt}"
    
    {
        echo "=== Dotfiles Installation Error Report ==="
        echo "Generated: $(date)"
        echo "Total Errors: $ERROR_COUNT"
        echo "Last Error: $LAST_ERROR"
        echo ""
        
        if [[ -f "$ERROR_LOG" ]]; then
            echo "=== Error Log Contents ==="
            cat "$ERROR_LOG"
        else
            echo "No error log found"
        fi
        
        echo ""
        echo "=== System Information ==="
        echo "OS: $(uname -a)"
        echo "Distribution: ${DISTRO:-unknown}"
        echo "User: $USER"
        echo "Shell: $SHELL"
        echo "Working Directory: $(pwd)"
        
        echo ""
        echo "=== Environment Variables ==="
        env | grep -E '^(HOME|PATH|SHELL|USER|DOTFILES|IS_WSL)' | sort
        
    } > "$report_file"
    
    success "Error report generated: $report_file"
}

# Clear error state
clear_error_state() {
    ERROR_COUNT=0
    LAST_ERROR=""
    ERROR_HANDLERS=()
    CLEANUP_FUNCTIONS=()
    
    if [[ -f "$ERROR_LOG" ]]; then
        local backup="${ERROR_LOG}.$(date +%Y%m%d-%H%M%S)"
        mv "$ERROR_LOG" "$backup"
        log "Error log backed up to: $backup"
    fi
}

# Test error handling
test_error_handling() {
    log "Testing error handling system..."
    
    # Save current state
    local saved_exit_on_error=$EXIT_ON_ERROR
    EXIT_ON_ERROR=false
    
    # Test basic error
    set +e
    false
    local test_result=$?
    set -e
    
    if [[ $test_result -ne 0 ]]; then
        success "Error handling test passed"
    else
        error "Error handling test failed"
    fi
    
    # Restore state
    EXIT_ON_ERROR=$saved_exit_on_error
}