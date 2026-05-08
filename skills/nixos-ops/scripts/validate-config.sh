#!/usr/bin/env bash
set -euo pipefail

# Pre-build validation for NixOS flake configuration
# Usage: bash validate-config.sh [hostname]
# Checks: git status, flake evaluation, disk space, /var/tmp writability

HOSTNAME="${1:-}"
REPO_DIR="${REPO_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
RESET='\033[0m'
ERRORS=0

info()  { echo -e "${GREEN}[OK]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET} $*"; }
fail()  { echo -e "${RED}[FAIL]${RESET} $*"; ERRORS=$((ERRORS + 1)); }

echo "=== NixOS Pre-Build Validation ==="
echo ""

# 1. Check git status for uncommitted changes
echo "--- Git Status ---"
if git -C "$REPO_DIR" diff --quiet 2>/dev/null && git -C "$REPO_DIR" diff --cached --quiet 2>/dev/null; then
    info "Working tree is clean"
else
    DIRTY_COUNT=$(git -C "$REPO_DIR" status --porcelain 2>/dev/null | wc -l)
    warn "Uncommitted changes detected ($DIRTY_COUNT files). Build will use working tree state."
    git -C "$REPO_DIR" status --short 2>/dev/null | head -10
    if [ "$DIRTY_COUNT" -gt 10 ]; then
        echo "  ... and $((DIRTY_COUNT - 10)) more"
    fi
fi
echo ""

# 2. Run nix flake check (eval only, no build)
echo "--- Flake Evaluation ---"
if nix flake check --no-build "$REPO_DIR" 2>&1; then
    info "Flake check passed (eval only)"
else
    fail "Flake check failed. Fix evaluation errors before building."
fi
echo ""

# 3. Check free disk space on /
echo "--- Disk Space ---"
ROOT_AVAIL_KB=$(df / --output=avail | tail -1 | tr -d ' ')
ROOT_AVAIL_GB=$((ROOT_AVAIL_KB / 1048576))
ROOT_AVAIL_MB=$((ROOT_AVAIL_KB / 1024))

if [ "$ROOT_AVAIL_GB" -lt 2 ]; then
    fail "CRITICAL: Only ${ROOT_AVAIL_MB}MB free on /. Build will likely fail."
    echo "  Run: sudo nix-collect-garbage -d && sudo nix store gc"
elif [ "$ROOT_AVAIL_GB" -lt 5 ]; then
    warn "Low disk space: ${ROOT_AVAIL_GB}GB free on /. Consider garbage collection."
    echo "  Run: sudo nix-collect-garbage --delete-older-than 7d"
else
    info "Disk space: ${ROOT_AVAIL_GB}GB free on /"
fi
echo ""

# 4. Check /var/tmp exists and is writable (nix uses it for builds)
echo "--- Build Temp Directory ---"
if [ -d /var/tmp ] && [ -w /var/tmp ]; then
    VARTMP_AVAIL_KB=$(df /var/tmp --output=avail | tail -1 | tr -d ' ')
    VARTMP_AVAIL_GB=$((VARTMP_AVAIL_KB / 1048576))
    if [ "$VARTMP_AVAIL_GB" -lt 2 ]; then
        warn "/var/tmp has only ${VARTMP_AVAIL_GB}GB free. Large builds may fail."
    else
        info "/var/tmp is writable with ${VARTMP_AVAIL_GB}GB free"
    fi
else
    fail "/var/tmp is missing or not writable. Nix builds will fail."
fi
echo ""

# 5. Evaluate specific host config if hostname provided
if [ -n "$HOSTNAME" ]; then
    echo "--- Host Evaluation: $HOSTNAME ---"
    if nix eval --show-trace "$REPO_DIR#nixosConfigurations.$HOSTNAME.config.system.stateVersion" 2>&1; then
        info "Host '$HOSTNAME' config evaluates successfully"
    else
        fail "Host '$HOSTNAME' config evaluation failed. Check --show-trace output above."
    fi
    echo ""
fi

# Summary
echo "=== Summary ==="
if [ "$ERRORS" -eq 0 ]; then
    info "All checks passed. Safe to build."
    exit 0
else
    fail "$ERRORS check(s) failed. Fix issues before building."
    exit 1
fi
