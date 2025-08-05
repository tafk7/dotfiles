#!/usr/bin/env bash
# Find and Replace - Safe text replacement with preview
# Usage: fr [--dry-run] [--interactive] <find> <replace> [directory]

set -euo pipefail

# Default values
DRY_RUN=false
INTERACTIVE=false
TARGET_DIR="."

# Exclusion patterns
EXCLUDE_DIRS=(.git .svn node_modules .backups __pycache__ .idea .vscode dist build)
EXCLUDE_EXTS=(jpg jpeg png gif bmp ico pdf zip tar gz bz2 7z rar exe dll so dylib)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --interactive)
            INTERACTIVE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--interactive] <find> <replace> [directory]"
            echo ""
            echo "Options:"
            echo "  --dry-run      Show what would be changed without modifying files"
            echo "  --interactive  Confirm each file before replacing"
            echo "  -h, --help     Show this help message"
            echo ""
            echo "Safely finds and replaces text in files, excluding binary files and"
            echo "common directories like .git, node_modules, etc."
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

# Validate remaining arguments
if [[ $# -lt 2 ]] || [[ $# -gt 3 ]]; then
    echo -e "${RED}Error: Invalid arguments${NC}"
    echo "Usage: $0 [--dry-run] [--interactive] <find> <replace> [directory]"
    exit 1
fi

OLD_STRING="$1"
NEW_STRING="$2"
TARGET_DIR="${3:-.}"

# Validate target directory
if [[ ! -d "$TARGET_DIR" ]]; then
    echo -e "${RED}Error: Directory '$TARGET_DIR' does not exist${NC}"
    exit 1
fi

# Build grep exclude arguments
GREP_EXCLUDES=""
for dir in "${EXCLUDE_DIRS[@]}"; do
    GREP_EXCLUDES="$GREP_EXCLUDES --exclude-dir=$dir"
done

# Build find exclude arguments for extensions
FIND_EXCLUDES=""
for ext in "${EXCLUDE_EXTS[@]}"; do
    FIND_EXCLUDES="$FIND_EXCLUDES -o -name '*.$ext'"
done

# Function to count matching files
count_matching_files() {
    grep -rl $GREP_EXCLUDES -F "$OLD_STRING" "$TARGET_DIR" 2>/dev/null | wc -l
}

# Function to get matching files
get_matching_files() {
    grep -rl $GREP_EXCLUDES -F "$OLD_STRING" "$TARGET_DIR" 2>/dev/null || true
}

# Show occurrences with context
echo -e "${BLUE}Searching for occurrences of '${OLD_STRING}'...${NC}"
echo ""

# Display matches with line numbers and context
if ! grep -rn --color=always $GREP_EXCLUDES -F "$OLD_STRING" "$TARGET_DIR" 2>/dev/null; then
    echo -e "${YELLOW}No occurrences found.${NC}"
    exit 0
fi

# Count affected files
FILE_COUNT=$(count_matching_files)
echo ""
echo -e "${BLUE}Found in ${FILE_COUNT} file(s)${NC}"

# Handle dry-run mode
if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo -e "${YELLOW}DRY RUN MODE - No files will be modified${NC}"
    echo -e "Would replace '${OLD_STRING}' with '${NEW_STRING}' in these files:"
    get_matching_files | sed 's/^/  /'
    exit 0
fi

# Confirm before proceeding
echo ""
read -r -p "Proceed with replacements? [y/N]: " confirm
if [[ "$confirm" != [yY] ]]; then
    echo -e "${YELLOW}Aborted.${NC}"
    exit 0
fi

# Function to replace in a single file
replace_in_file() {
    local file="$1"
    perl -pi -e "s/\Q$OLD_STRING\E/$NEW_STRING/g" "$file"
}

# Function to show file context in interactive mode
show_file_context() {
    local file="$1"
    echo ""
    echo -e "${BLUE}=== $file ===${NC}"
    grep -n --color=always -F "$OLD_STRING" "$file" | head -5
    local match_count=$(grep -c -F "$OLD_STRING" "$file")
    if [[ $match_count -gt 5 ]]; then
        echo -e "${YELLOW}... and $((match_count - 5)) more matches${NC}"
    fi
}

# Perform replacements
echo ""
if [[ "$INTERACTIVE" == "true" ]]; then
    # Interactive mode - confirm each file
    echo -e "${BLUE}Interactive mode - confirm each file:${NC}"
    
    processed=0
    skipped=0
    
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        
        show_file_context "$file"
        echo ""
        read -r -p "Replace in this file? [y/N/q]: " file_confirm
        
        case "$file_confirm" in
            [yY])
                replace_in_file "$file"
                echo -e "${GREEN}✓ Replaced${NC}"
                ((processed++))
                ;;
            [qQ])
                echo -e "${YELLOW}Quitting...${NC}"
                break
                ;;
            *)
                echo -e "${YELLOW}Skipped${NC}"
                ((skipped++))
                ;;
        esac
    done < <(get_matching_files)
    
    echo ""
    echo -e "${GREEN}Replacement complete:${NC} $processed file(s) modified, $skipped file(s) skipped"
    
else
    # Non-interactive mode - replace in all files
    echo -e "${BLUE}Replacing in $FILE_COUNT file(s)...${NC}"
    
    # Build find command that excludes binary extensions
    find_cmd="find \"$TARGET_DIR\" -type f"
    find_cmd="$find_cmd \\( -name '*.txt' -o -name '*.md' -o -name '*.sh' -o -name '*.bash'"
    find_cmd="$find_cmd -o -name '*.zsh' -o -name '*.fish' -o -name '*.py' -o -name '*.js'"
    find_cmd="$find_cmd -o -name '*.ts' -o -name '*.jsx' -o -name '*.tsx' -o -name '*.java'"
    find_cmd="$find_cmd -o -name '*.c' -o -name '*.cpp' -o -name '*.h' -o -name '*.hpp'"
    find_cmd="$find_cmd -o -name '*.go' -o -name '*.rs' -o -name '*.rb' -o -name '*.php'"
    find_cmd="$find_cmd -o -name '*.pl' -o -name '*.lua' -o -name '*.vim' -o -name '*.yaml'"
    find_cmd="$find_cmd -o -name '*.yml' -o -name '*.json' -o -name '*.xml' -o -name '*.html'"
    find_cmd="$find_cmd -o -name '*.css' -o -name '*.scss' -o -name '*.sass' -o -name '*.less'"
    find_cmd="$find_cmd -o -name '*.sql' -o -name '*.conf' -o -name '*.cfg' -o -name '*.ini'"
    find_cmd="$find_cmd -o -name '*.toml' -o -name '*.env' -o -name '*.gitignore' -o -name '*.dockerignore'"
    find_cmd="$find_cmd -o -name 'Makefile' -o -name 'Dockerfile' -o -name 'Vagrantfile'"
    find_cmd="$find_cmd -o -name '*.log' -o ! -name '*.*' \\)" # Include files without extensions
    
    # Add directory exclusions
    for dir in "${EXCLUDE_DIRS[@]}"; do
        find_cmd="$find_cmd -path '*/$dir' -prune -o"
    done
    
    # Execute replacement only on files that contain the string
    processed=0
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        if grep -qF "$OLD_STRING" "$file" 2>/dev/null; then
            replace_in_file "$file"
            ((processed++))
            # Show progress for large operations
            if [[ $((processed % 10)) -eq 0 ]]; then
                echo -ne "\r${GREEN}Progress: $processed/$FILE_COUNT files processed...${NC}"
            fi
        fi
    done < <(eval "$find_cmd -type f -print 2>/dev/null")
    
    echo -e "\r${GREEN}✓ Replacement complete:${NC} Replaced '${OLD_STRING}' with '${NEW_STRING}' in $processed file(s)"
fi