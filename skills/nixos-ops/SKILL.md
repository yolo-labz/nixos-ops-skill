---
name: nixos-ops
description: >
  This skill should be used when working with NixOS configuration, Nix flakes,
  Home Manager modules, or system rebuilds. Covers "rebuild NixOS", "debug nix build",
  "create nix module", "fix nix error", "infinite recursion", "attribute missing",
  "nh os switch", flake.lock updates, and declarative service configuration. Use
  whenever the user mentions nix, nixos-rebuild, configuration.nix, home-manager,
  mkOption, mkIf, or any .nix file editing, even if they don't explicitly ask for
  NixOS help.
version: 1.0.0
---

# NixOS Operations Skill

## Repository Architecture

This repo is a multi-host NixOS + nix-darwin flake using flake-parts. All hosts share a single `main` branch with no per-host branches. **NEVER push directly to `main`** — all changes go through feature branches merged via PR.

### Mandatory PR Workflow

1. `git checkout -b NNN-short-description` — branch from up-to-date main (NNN = next PR number)
2. Make changes, commit with conventional commits
3. `git fetch origin main && git rebase origin/main` — stay current with main
4. `git push -u origin HEAD` — push feature branch
5. `gh pr create --title "type: description" --body "..."` — create PR with context
6. Wait for CI checks (lint, eval-linux, eval-darwin, flake-health) to pass
7. Review Copilot / static analysis feedback and fix issues
8. Check recent merged PRs (`gh pr list --state merged --limit 5`) for cross-host awareness
9. `gh pr merge --squash --delete-branch` — merge only when all checks pass

### Module Hierarchy

```
hosts/                          # Per-machine config (system-level)
  desktop/                      # Intel Xeon E5-2699 v4, AMD GPU, GNOME Wayland, 94GB RAM
  laptop/                       # NVIDIA GTX 1650, gaming specialisation
  server/                       # Proxmox VM, headless, no Home Manager
  macbook-pro/                  # Apple M5, nix-darwin

modules/
  core/                         # Boot, fonts, locale, nix settings, docker-dns
  shared/                       # Cross-platform system modules (NixOS + darwin)
    rclone-mount.nix            # Cloud storage mount (systemd/launchd)
  services/                     # NixOS-only systemd services
    backup.nix                  # Restic to S3
    printing.nix                # CUPS + Avahi
    cloudflare-tunnel.nix       # Cloudflare Tunnel
  home/                         # Home Manager modules (user-level, all HM hosts)
    shell.nix                   # Zsh + P10k
    claude-code.nix             # Claude Code plugins, agents, rules, memory
    packages.nix                # User packages
    git.nix                     # Git config
  virtualization/               # Libvirt, Docker
  gaming/                       # Steam, Lutris, game-related config
  desktop/                      # GNOME, display manager, Wayland
  hardware/                     # GPU drivers, firmware
  networking/                   # Tailscale, firewall, DNS
  packages/                     # System-level package groups

profiles/                       # Role-based profiles
  common.nix                    # Shared across all NixOS hosts
  desktop.nix                   # Desktop workstation profile
  laptop.nix                    # Laptop-specific profile
  server.nix                    # Server profile

dotfiles/                       # Source files referenced by Home Manager
  claude-commands/              # 9 slash commands for Claude Code
  nixos-ops-skill/              # This skill plugin

secrets/                        # sops-nix encrypted secrets
user-scripts/                   # Utility scripts (nixswitch, etc.)
```

### Key Config Patterns

- All `.nix` files use `alejandra` formatting (2-space indent, trailing commas).
- Explicit `lib.` prefixes everywhere. Never `with lib;` in new code.
- Home Manager runs as a NixOS/darwin module, not standalone.
- The server host does NOT use Home Manager.
- Catppuccin Mocha theme applied via catppuccin/nix (single declaration).

## Host Quick Reference

| Host | Hostname Key | Platform | Rebuild | Rollback | Notable |
|------|-------------|----------|---------|----------|---------|
| Desktop | `"desktop"` | NixOS x86_64 | `nh os switch .` | `nixos-rebuild switch --rollback` | AMD RX 5700 XT, GNOME Wayland, 94GB RAM, ZRAM+earlyoom, docker socket-activated |
| Laptop | `"nixos-laptop"` | NixOS x86_64 | `nh os switch .` | `nixos-rebuild switch --rollback` | NVIDIA GTX 1650, kernel pinned 6.12.x, gaming specialisation |
| Server | `"server"` | NixOS x86_64 | `nh os switch .` | `nixos-rebuild switch --rollback` | Proxmox VM, NO Home Manager, Qt6 disabled, static DNS, Plex LD_LIBRARY_PATH fix |
| MacBook | `"Pedros-MacBook-Pro"` | nix-darwin aarch64 | `nh darwin switch .` | `darwin-rebuild switch --rollback` | Apple M5, `nix.enable = false` (Determinate), Homebrew for GUI apps |

## Build Workflow

### Pre-Build Checks

1. Run `scripts/validate-config.sh` or perform manual checks:
   - Verify no uncommitted changes that could affect the build: `git status`
   - Run `nix flake check --no-build` to catch eval errors without building
   - Check free disk space on `/` (warn below 5GB, abort below 2GB)
2. Run `scripts/check-disk-before-build.sh` to detect runaway logs (prevents auditd-style 289GB incidents).

### Build and Deploy

3. Build the current host configuration:
   - Linux hosts: `nh os switch .`
   - Darwin host: `nh darwin switch .`
4. Verify the build succeeded:
   - Check for failed services: `systemctl --failed`
   - Review boot journal: `journalctl -xe -b`

### On Build Failure

5. Parse the error output and consult `references/common-errors.md` for known patterns.
6. For evaluation errors, get a full trace:
   ```bash
   nix eval --show-trace .#nixosConfigurations.<hostname>.config.<option.path>
   ```
7. For build errors, check:
   - Flake inputs are up to date: `nix flake metadata`
   - Binary cache is reachable: `nix store ping --store https://cache.nixos.org`
8. Binary-search isolation: comment out imports in the host's `configuration.nix` to find the culprit module.

### Rollback

9. Rollback to the previous generation:
   - `nixos-rebuild switch --rollback` (NixOS)
   - `darwin-rebuild switch --rollback` (darwin)
   - Or select a previous generation from the GRUB boot menu.

### Post-Build Verification

10. Run `scripts/diff-generations.sh` to compare the new generation against the previous one.
11. Verify critical services are running: `systemctl status <service-name>`

## Error Diagnosis Workflow

1. **Capture the error** — copy the full error message, including any `error:` and `trace:` lines.
2. **Classify the error type**:
   - Evaluation error (syntax, type mismatch, infinite recursion, missing attribute)
   - Build error (hash mismatch, download failure, compilation failure)
   - Runtime error (service crash, permission denied, missing dependency)
   - Activation error (collision, symlink conflict)
3. **Check known patterns** — consult `references/common-errors.md` for this repo's historical errors.
4. **For eval errors**:
   - Run `nix eval --show-trace .#nixosConfigurations.<host>.config` to get the full trace.
   - Check for `config` self-reference inside an `options` block (common infinite recursion cause).
   - Check for circular `imports` between modules.
   - Verify option types match (e.g., passing a string where `listOf str` is expected).
5. **For build errors**:
   - Hash mismatch: run `nix-prefetch-url --unpack <url>` to get the correct hash.
   - Missing binary cache: check `nix.settings.substituters` in flake config.
   - Unfree package blocked: ensure `nixpkgs.config.allowUnfree = true` is set.
6. **For runtime errors**:
   - Check service status: `systemctl status <service>`
   - Check logs: `journalctl -u <service> --since "10 min ago"`
   - Check file permissions and ownership.
7. **Binary-search isolation**:
   - Comment out half the imports in the host config.
   - Rebuild. If it succeeds, the problem is in the commented-out half.
   - Repeat until the offending module is identified.

## Module Creation Workflow

1. **Determine the correct directory** based on module type:
   - NixOS-only system service: `modules/services/`
   - Cross-platform system module: `modules/shared/`
   - Home Manager user config: `modules/home/`
   - Boot/locale/nix settings: `modules/core/`
   - Other NixOS-only categories: `modules/<category>/`
2. **Choose the archetype** — refer to `references/module-patterns.md` for the three archetypes with code templates.
3. **Follow option conventions** — refer to `references/option-conventions.md` for typing, naming, and formatting rules.
4. **Implement the module**:
   - Use explicit `lib.` prefixes (never `with lib;`).
   - Use `lib.mkIf cfg.enable { ... }` for conditional config.
   - Use `lib.mkEnableOption "description"` for the enable flag.
   - Platform-conditional code: see `references/platform-branching.md`.
5. **Register the module**:
   - Add to the appropriate `default.nix` or imports list.
   - Add to the relevant host config or profile if not auto-imported.
6. **Test**:
   - Run `nix flake check --no-build` to verify evaluation.
   - Build the affected host: `nh os switch .` or `nh darwin switch .`

## Scripts Reference

| Script | Purpose | Usage |
|--------|---------|-------|
| `scripts/validate-config.sh` | Pre-build: git status, flake check, disk space | `bash scripts/validate-config.sh [hostname]` |
| `scripts/diff-generations.sh` | Compare current vs previous generation | `bash scripts/diff-generations.sh` |
| `scripts/find-option.sh` | Search NixOS/HM options by keyword | `bash scripts/find-option.sh <keyword>` |
| `scripts/check-disk-before-build.sh` | Check disk space, detect runaway logs | `bash scripts/check-disk-before-build.sh` |

All scripts are in `skills/nixos-ops/scripts/` within this plugin directory. Run them with `bash <path>`.

## Reference Index

| Topic | File | Summary |
|-------|------|---------|
| Known error patterns and fixes | `references/common-errors.md` | 12 documented errors from repo history with root cause and fix |
| Module archetypes for this repo | `references/module-patterns.md` | 3 archetypes: NixOS-only, cross-platform shared, Home Manager |
| Host profiles and quirks | `references/host-profiles.md` | Detailed specs for all 4 hosts including hardware, GPU, RAM, secrets |
| Platform detection patterns | `references/platform-branching.md` | Two patterns for user-level and system-level platform branching |
| Option naming and typing | `references/option-conventions.md` | Alejandra formatting, mkOption patterns, priority ordering |

## Critical Constraints

- **Server has no Home Manager** — never add HM config to the server host.
- **Single `main` branch** — all hosts build from the same branch. **NEVER push directly to `main`** — use feature branches + PR.
- **Mandatory PR workflow** — create branch, push, create PR, wait for CI, review feedback, merge. See "Mandatory PR Workflow" above.
- **No `with lib;`** — always use explicit `lib.` prefixes in new code.
- **No `builtins.getEnv`** — fails in pure evaluation mode.
- **Alejandra formatting** — 2-space indent, trailing commas, run `alejandra` before committing.
- **Conventional commits** — `feat:`, `fix:`, `refactor:`, `chore:`, `docs:` prefixes.
- **Catppuccin Mocha** — applied via catppuccin/nix module, do not hardcode theme values in new modules.
- **NOPASSWD sudoers** — `nh` requires NOPASSWD for the `env` command. Fallback: set `NH_SUDO_ASKPASS`.
- **Disk space awareness** — the auditd incident (289GB logs) means always check disk before builds.
