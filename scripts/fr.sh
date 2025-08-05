#!/usr/bin/env bash

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Usage: $0 <string_to_find> <string_to_replace_with> [directory_path]"
  exit 1
fi

OLD_STRING="$1"
NEW_STRING="$2"
TARGET_DIR="${3:-.}"

echo "Detected occurrences of '$OLD_STRING':"
grep -rn --color=always -F "$OLD_STRING" "$TARGET_DIR" || echo "No occurrences found."

read -r -p "Proceed with replacements? [y/N]: " confirm
if [[ "$confirm" != [yY] ]]; then
  echo "Aborted."
  exit 0
fi

find "$TARGET_DIR" -type f -exec perl -pi -e "s/\Q$OLD_STRING\E/$NEW_STRING/g" {} +
echo "Replacement complete."

