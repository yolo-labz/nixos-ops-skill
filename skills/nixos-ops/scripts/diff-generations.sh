#!/usr/bin/env bash
set -euo pipefail

# Compare NixOS generations to see what changed
# Usage: bash diff-generations.sh

PROFILE="/nix/var/nix/profiles/system"
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RESET='\033[0m'

echo "=== NixOS Generation Comparison ==="
echo ""

# 1. Show current and previous generation numbers
CURRENT=$(readlink "$PROFILE" 2>/dev/null || echo "unknown")
CURRENT_NUM=$(echo "$CURRENT" | grep -oP 'system-\K\d+' || echo "?")

# List recent generations
echo -e "${BLUE}--- Recent Generations ---${RESET}"
GENERATIONS=$(ls -1d /nix/var/nix/profiles/system-*-link 2>/dev/null | sort -t- -k2 -n | tail -5)
if [ -z "$GENERATIONS" ]; then
    echo "No generations found. Is this a NixOS system?"
    exit 1
fi

for gen in $GENERATIONS; do
    GEN_NUM=$(echo "$gen" | grep -oP 'system-\K\d+')
    GEN_DATE=$(stat -c '%y' "$gen" 2>/dev/null | cut -d'.' -f1)
    if [ "$gen" = "/nix/var/nix/profiles/system-${CURRENT_NUM}-link" ]; then
        echo -e "  ${GREEN}* Generation $GEN_NUM${RESET} ($GEN_DATE) [current]"
    else
        echo "    Generation $GEN_NUM ($GEN_DATE)"
    fi
done
echo ""

# 2. Run nix profile diff-closures to show package changes
echo -e "${BLUE}--- Package Changes (current vs previous) ---${RESET}"
if command -v nix &>/dev/null; then
    nix profile diff-closures --profile "$PROFILE" 2>/dev/null | tail -40 || echo "  Unable to compute diff-closures."
else
    echo "  nix command not found."
fi
echo ""

# 3. Show size difference between current and previous generation
echo -e "${BLUE}--- Closure Size ---${RESET}"
if [ "$CURRENT_NUM" != "?" ] && [ "$CURRENT_NUM" -gt 1 ]; then
    PREV_NUM=$((CURRENT_NUM - 1))
    PREV_LINK="/nix/var/nix/profiles/system-${PREV_NUM}-link"

    if [ -L "$PREV_LINK" ]; then
        CURRENT_SIZE=$(nix path-info -S "$PROFILE" 2>/dev/null | awk '{print $2}' || echo "0")
        PREV_SIZE=$(nix path-info -S "$PREV_LINK" 2>/dev/null | awk '{print $2}' || echo "0")

        if [ "$CURRENT_SIZE" != "0" ] && [ "$PREV_SIZE" != "0" ]; then
            CURRENT_MB=$((CURRENT_SIZE / 1048576))
            PREV_MB=$((PREV_SIZE / 1048576))
            DIFF_MB=$((CURRENT_MB - PREV_MB))

            echo "  Previous (gen $PREV_NUM): ${PREV_MB}MB"
            echo "  Current  (gen $CURRENT_NUM): ${CURRENT_MB}MB"
            if [ "$DIFF_MB" -gt 0 ]; then
                echo -e "  ${YELLOW}Delta: +${DIFF_MB}MB${RESET}"
            elif [ "$DIFF_MB" -lt 0 ]; then
                echo -e "  ${GREEN}Delta: ${DIFF_MB}MB${RESET}"
            else
                echo "  Delta: no change"
            fi
        else
            echo "  Unable to compute closure sizes."
        fi
    else
        echo "  Previous generation link not found: $PREV_LINK"
    fi
else
    echo "  Cannot determine previous generation."
fi
echo ""

# 4. Show kernel version if it changed
echo -e "${BLUE}--- Kernel ---${RESET}"
CURRENT_KERNEL=$(readlink "${PROFILE}/kernel" 2>/dev/null | grep -oP 'linux-\K[0-9.]+' || echo "unknown")
if [ "$CURRENT_NUM" != "?" ] && [ "$CURRENT_NUM" -gt 1 ]; then
    PREV_KERNEL=$(readlink "${PREV_LINK}/kernel" 2>/dev/null | grep -oP 'linux-\K[0-9.]+' || echo "unknown")
    if [ "$CURRENT_KERNEL" = "$PREV_KERNEL" ]; then
        echo "  Kernel: $CURRENT_KERNEL (unchanged)"
    else
        echo -e "  ${YELLOW}Kernel changed: $PREV_KERNEL -> $CURRENT_KERNEL${RESET}"
    fi
else
    echo "  Current kernel: $CURRENT_KERNEL"
fi
