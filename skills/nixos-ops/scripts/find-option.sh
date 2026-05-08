#!/usr/bin/env bash
set -euo pipefail

# Search NixOS options by keyword
# Usage: bash find-option.sh <keyword>
# Searches local module options first, then suggests online resources.

KEYWORD="${1:-}"
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

if [ -z "$KEYWORD" ]; then
    echo "Usage: bash find-option.sh <keyword>"
    echo ""
    echo "Examples:"
    echo "  bash find-option.sh printing"
    echo "  bash find-option.sh backup"
    echo "  bash find-option.sh rclone"
    echo "  bash find-option.sh zsh"
    exit 1
fi

REPO_DIR="${REPO_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME/NixOS")}"

echo "=== Option Search: '$KEYWORD' ==="
echo ""

# 1. Search local module options (options.* declarations)
echo -e "${BLUE}--- Local Module Options ---${RESET}"
OPTION_MATCHES=$(grep -rn "options\.\|mkOption\|mkEnableOption" "$REPO_DIR/modules/" 2>/dev/null | grep -i "$KEYWORD" || true)

if [ -n "$OPTION_MATCHES" ]; then
    echo "$OPTION_MATCHES" | while IFS= read -r line; do
        FILE=$(echo "$line" | cut -d: -f1 | sed "s|$REPO_DIR/||")
        LINE_NUM=$(echo "$line" | cut -d: -f2)
        CONTENT=$(echo "$line" | cut -d: -f3- | sed 's/^[[:space:]]*//')
        echo -e "  ${GREEN}$FILE:$LINE_NUM${RESET}"
        echo "    $CONTENT"
    done
else
    echo "  No local option declarations found matching '$KEYWORD'."
fi
echo ""

# 2. Search local config usage (config.* references)
echo -e "${BLUE}--- Local Config Usage ---${RESET}"
CONFIG_MATCHES=$(grep -rn "config\.\|enable\s*=" "$REPO_DIR/modules/" "$REPO_DIR/hosts/" "$REPO_DIR/profiles/" 2>/dev/null | grep -i "$KEYWORD" | head -15 || true)

if [ -n "$CONFIG_MATCHES" ]; then
    echo "$CONFIG_MATCHES" | while IFS= read -r line; do
        FILE=$(echo "$line" | cut -d: -f1 | sed "s|$REPO_DIR/||")
        LINE_NUM=$(echo "$line" | cut -d: -f2)
        CONTENT=$(echo "$line" | cut -d: -f3- | sed 's/^[[:space:]]*//')
        echo -e "  ${GREEN}$FILE:$LINE_NUM${RESET}"
        echo "    $CONTENT"
    done
else
    echo "  No local config usage found matching '$KEYWORD'."
fi
echo ""

# 3. Search with nixos-option if available
echo -e "${BLUE}--- System Option Lookup ---${RESET}"
if command -v nixos-option &>/dev/null; then
    NIXOS_RESULTS=$(nixos-option "$KEYWORD" 2>/dev/null | head -20 || true)
    if [ -n "$NIXOS_RESULTS" ]; then
        echo "$NIXOS_RESULTS"
    else
        echo "  nixos-option found no match for '$KEYWORD'."
    fi
else
    echo "  nixos-option not available. Use online search instead."
fi
echo ""

# 4. Suggest online resources
echo -e "${YELLOW}--- Online Resources ---${RESET}"
ENCODED_KEYWORD=$(echo "$KEYWORD" | sed 's/ /+/g')
echo "  NixOS options:        https://search.nixos.org/options?query=$ENCODED_KEYWORD"
echo "  Home Manager options: https://home-manager-options.extranix.com/?query=$ENCODED_KEYWORD"
echo "  Nix packages:         https://search.nixos.org/packages?query=$ENCODED_KEYWORD"
