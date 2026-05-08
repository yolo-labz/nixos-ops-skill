#!/usr/bin/env bash
set -euo pipefail

# Disk space check before nix build
# Usage: bash check-disk-before-build.sh
# Checks: root free space, /nix/store size, audit log runaway, old generations

RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RESET='\033[0m'
WARNINGS=0
CRITICAL=0

info()  { echo -e "  ${GREEN}[OK]${RESET} $*"; }
warn()  { echo -e "  ${YELLOW}[WARN]${RESET} $*"; WARNINGS=$((WARNINGS + 1)); }
crit()  { echo -e "  ${RED}[CRITICAL]${RESET} $*"; CRITICAL=$((CRITICAL + 1)); }

echo "=== Pre-Build Disk Space Check ==="
echo ""

# 1. Check / free space
echo -e "${BLUE}--- Root Filesystem ---${RESET}"
ROOT_AVAIL_KB=$(df / --output=avail | tail -1 | tr -d ' ')
ROOT_TOTAL_KB=$(df / --output=size | tail -1 | tr -d ' ')
ROOT_USED_PCT=$(df / --output=pcent | tail -1 | tr -d ' %')
ROOT_AVAIL_GB=$((ROOT_AVAIL_KB / 1048576))
ROOT_TOTAL_GB=$((ROOT_TOTAL_KB / 1048576))

if [ "$ROOT_AVAIL_GB" -lt 2 ]; then
    crit "Only ${ROOT_AVAIL_GB}GB free on / (${ROOT_USED_PCT}% used of ${ROOT_TOTAL_GB}GB). BUILD WILL FAIL."
elif [ "$ROOT_AVAIL_GB" -lt 5 ]; then
    warn "Low: ${ROOT_AVAIL_GB}GB free on / (${ROOT_USED_PCT}% used of ${ROOT_TOTAL_GB}GB)."
else
    info "${ROOT_AVAIL_GB}GB free on / (${ROOT_USED_PCT}% used of ${ROOT_TOTAL_GB}GB)"
fi
echo ""

# 2. Show /nix/store size
echo -e "${BLUE}--- Nix Store ---${RESET}"
if [ -d /nix/store ]; then
    NIX_STORE_SIZE=$(du -sh /nix/store 2>/dev/null | cut -f1)
    NIX_STORE_ITEMS=$(ls /nix/store 2>/dev/null | wc -l)
    info "Nix store: $NIX_STORE_SIZE ($NIX_STORE_ITEMS items)"
else
    warn "/nix/store not found. Is Nix installed?"
fi
echo ""

# 3. Check for runaway log files (auditd 289GB incident prevention)
echo -e "${BLUE}--- Runaway Log Detection ---${RESET}"
AUDIT_DIR="/var/log/audit"
if [ -d "$AUDIT_DIR" ]; then
    AUDIT_SIZE_KB=$(du -sk "$AUDIT_DIR" 2>/dev/null | cut -f1)
    AUDIT_SIZE_MB=$((AUDIT_SIZE_KB / 1024))
    AUDIT_SIZE_GB=$((AUDIT_SIZE_KB / 1048576))

    if [ "$AUDIT_SIZE_GB" -gt 1 ]; then
        crit "AUDIT LOG ALERT: /var/log/audit/ is ${AUDIT_SIZE_GB}GB!"
        echo "    This repo has a history of auditd filling 289GB of disk space."
        echo "    Fix: security.auditd.enable = false; security.audit.enable = false;"
        echo "    Immediate: sudo rm -f /var/log/audit/audit.log.*"
    elif [ "$AUDIT_SIZE_MB" -gt 100 ]; then
        warn "Audit logs at ${AUDIT_SIZE_MB}MB in /var/log/audit/. Monitor growth."
    else
        info "Audit logs: ${AUDIT_SIZE_MB}MB (healthy)"
    fi
else
    info "No audit log directory (auditd disabled or not installed)"
fi

# Check /var/log total size
VARLOG_SIZE_KB=$(du -sk /var/log 2>/dev/null | cut -f1)
VARLOG_SIZE_MB=$((VARLOG_SIZE_KB / 1024))
VARLOG_SIZE_GB=$((VARLOG_SIZE_KB / 1048576))

if [ "$VARLOG_SIZE_GB" -gt 5 ]; then
    warn "/var/log is ${VARLOG_SIZE_GB}GB. Check for runaway logs."
    echo "    Largest files:"
    find /var/log -type f -size +100M -exec ls -lh {} \; 2>/dev/null | head -5 || true
elif [ "$VARLOG_SIZE_GB" -gt 1 ]; then
    info "/var/log: ${VARLOG_SIZE_GB}GB"
else
    info "/var/log: ${VARLOG_SIZE_MB}MB"
fi
echo ""

# 4. Count old NixOS generations eligible for garbage collection
echo -e "${BLUE}--- Generations ---${RESET}"
PROFILE="/nix/var/nix/profiles/system"
if [ -L "$PROFILE" ]; then
    CURRENT_NUM=$(readlink "$PROFILE" | grep -oP 'system-\K\d+' || echo "0")
    TOTAL_GENS=$(ls -1d /nix/var/nix/profiles/system-*-link 2>/dev/null | wc -l)
    OLD_GENS=$((TOTAL_GENS - 1))  # Exclude current

    if [ "$OLD_GENS" -gt 10 ]; then
        warn "$OLD_GENS old generations (current: $CURRENT_NUM). Consider cleanup:"
        echo "    sudo nix-collect-garbage --delete-older-than 7d"
    elif [ "$OLD_GENS" -gt 0 ]; then
        info "$OLD_GENS old generation(s) (current: $CURRENT_NUM)"
    else
        info "Only current generation exists ($CURRENT_NUM)"
    fi

    # Estimate reclaimable space
    if command -v nix &>/dev/null && [ "$OLD_GENS" -gt 3 ]; then
        echo "    Tip: Run 'nix store gc --dry-run' to see reclaimable space."
    fi
else
    info "No system profile found (is this a NixOS system?)"
fi

# Also check home-manager generations
HM_PROFILE="/nix/var/nix/profiles/per-user/$USER/home-manager"
if [ -L "$HM_PROFILE" ]; then
    HM_GENS=$(ls -1d /nix/var/nix/profiles/per-user/"$USER"/home-manager-*-link 2>/dev/null | wc -l)
    if [ "$HM_GENS" -gt 20 ]; then
        warn "$HM_GENS Home Manager generations. Cleanup: home-manager expire-generations '-7 days'"
    else
        info "$HM_GENS Home Manager generation(s)"
    fi
fi
echo ""

# 5. Summary with recommendations
echo "=== Summary ==="
if [ "$CRITICAL" -gt 0 ]; then
    echo -e "${RED}$CRITICAL critical issue(s). DO NOT BUILD until resolved.${RESET}"
    echo ""
    echo "Recommended actions:"
    echo "  1. sudo nix-collect-garbage -d"
    echo "  2. sudo nix store gc"
    echo "  3. Check for runaway logs: du -sh /var/log/*/ | sort -rh | head"
    exit 1
elif [ "$WARNINGS" -gt 0 ]; then
    echo -e "${YELLOW}$WARNINGS warning(s). Build may succeed but consider cleanup.${RESET}"
    echo ""
    echo "Recommended:"
    echo "  sudo nix-collect-garbage --delete-older-than 7d"
    exit 0
else
    echo -e "${GREEN}All checks passed. Disk space is healthy for building.${RESET}"
    exit 0
fi
