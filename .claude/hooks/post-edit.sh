#!/usr/bin/env bash
# Post-edit hook: format the file that was just edited.
set -euo pipefail

file="$(jq -r '.tool_input.file_path // empty')"
[ "$file" != "" ] && [ -f "$file" ] || exit 0

case "$file" in
  *.tf | *.tftest.hcl)
    terraform fmt "$file" > /dev/null 2>&1 || true
    ;;
  *.sh)
    shellharden --replace "$file" 2> /dev/null || true
    chmod +x "$file"
    ;;
  *.md)
    markdownlint-cli2 --fix "$file" > /dev/null 2>&1 || true
    ;;
esac
