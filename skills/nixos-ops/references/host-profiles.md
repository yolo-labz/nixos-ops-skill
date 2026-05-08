# Host Profiles

Detailed specifications for all 4 hosts in this NixOS + nix-darwin flake. The hostname keys match the `hostProfiles` attrset in `modules/home/claude-code.nix`.

---

## Desktop

| Property | Value |
|----------|-------|
| **Hostname key** | `"desktop"` |
| **Profile name** | `desktop` |
| **Platform** | NixOS x86_64-linux |
| **Tier** | `full` |
| **Role** | Secondary workstation — gaming, heavy compute, frontend dev |
| **Desktop** | GNOME on Wayland |
| **GPU** | AMD RX 5700 XT (AMDGPU open-source driver) |
| **CPU** | Intel Xeon E5-2699 v4 (22C/44T, 2.2GHz base / 3.6GHz turbo) |
| **RAM** | 94GB |
| **Memory management** | ZRAM swap + earlyoom |
| **Home Manager** | Yes |
| **Rebuild** | `nh os switch .` |
| **Rollback** | `nixos-rebuild switch --rollback` |
| **Secrets file** | `secrets/desktop.yaml` (sops-nix) |
| **Docker** | Socket-activated (on-demand startup) |
| **Notable quirks** | auditd disabled after 289GB log incident; AMDGPU needs `amdgpu.ppfeaturemask` for overclocking; uses Catppuccin Mocha GNOME theme |

### Desktop-Specific Config Files

- `hosts/desktop/configuration.nix` — main host config
- `hosts/desktop/boot.nix` — bootloader, kernel params
- `hosts/desktop/networking.nix` — network config
- `hosts/desktop/hardware-configuration.nix` — auto-generated hardware scan

---

## Laptop

| Property | Value |
|----------|-------|
| **Hostname key** | `"nixos-laptop"` |
| **Profile name** | `laptop` |
| **Platform** | NixOS x86_64-linux |
| **Tier** | `standard` |
| **Role** | Portable — light dev, note-taking, browsing |
| **Desktop** | GNOME on Wayland (with X11 fallback for NVIDIA) |
| **GPU** | NVIDIA GTX 1650 (proprietary driver) |
| **CPU** | Intel |
| **Home Manager** | Yes |
| **Rebuild** | `nh os switch .` |
| **Rollback** | `nixos-rebuild switch --rollback` |
| **Secrets file** | `secrets/laptop.yaml` (sops-nix) |
| **Notable quirks** | Kernel pinned to 6.12.x (NVIDIA incompatible with 6.17+); has gaming specialisation (NixOS specialisation for game-optimized config); battery-conscious power management; Intel/NVIDIA hybrid graphics (PRIME offload) |

### Laptop-Specific Config Files

- `hosts/laptop/configuration.nix` — main host config
- `hosts/laptop/hardware-configuration.nix` — auto-generated hardware scan

---

## Server

| Property | Value |
|----------|-------|
| **Hostname key** | `"server"` |
| **Profile name** | `server` |
| **Platform** | NixOS x86_64-linux |
| **Tier** | `minimal` |
| **Role** | Home server — media services, Tailscale, containers |
| **Desktop** | None (headless) |
| **GPU** | None (Proxmox VM, no passthrough) |
| **Home Manager** | **NO** — critical constraint, never add HM config for server |
| **Rebuild** | `nh os switch .` |
| **Rollback** | `nixos-rebuild switch --rollback` |
| **Secrets file** | `secrets/server.yaml` (sops-nix) |
| **Notable quirks** | Proxmox VM with HDD-backed storage; Qt6 force-disabled; static DNS; Plex requires `LD_LIBRARY_PATH=""` fix for glibc mismatch; `kernel.hung_task_timeout_secs = 300` for jbd2 panic prevention; Cloudflare tunnel (currently broken); no desktop environment, no display manager |

### Server-Specific Config Files

- `hosts/server/configuration.nix` — main host config
- `hosts/server/hardware-configuration.nix` — auto-generated hardware scan

### Server Constraints

- No Home Manager: all user-level config must be in system-level modules or host config.
- No GUI packages: avoid pulling in X11/Wayland/GTK/Qt dependencies.
- Limited resources: avoid heavy builds; prefer binary cache hits.
- HDD I/O: operations that write heavily to disk can trigger jbd2 hung task warnings.

---

## MacBook Pro

| Property | Value |
|----------|-------|
| **Hostname key** | `"Pedros-MacBook-Pro"` |
| **Profile name** | `macbook-pro` |
| **Platform** | nix-darwin aarch64-darwin |
| **Tier** | `full` |
| **Role** | Primary development machine — full-stack dev, AI coding, freelance work |
| **Desktop** | macOS (native) |
| **GPU** | Apple M5 integrated |
| **Home Manager** | Yes (as nix-darwin module) |
| **Rebuild** | `nh darwin switch .` |
| **Rollback** | `darwin-rebuild switch --rollback` |
| **Secrets file** | `secrets/macbook.yaml` (sops-nix) |
| **Notable quirks** | `nix.enable = false` (Determinate Nix installer manages nix daemon); Homebrew for GUI apps (nix-homebrew manages brew itself); marksman LSP excluded (pulls dotnet SDK); macFUSE needed for rclone mount; Ghostty + Zellij terminal |

### MacBook-Specific Config Files

- `hosts/macbook-pro/configuration.nix` — nix-darwin host config
- `hosts/macbook-pro/homebrew.nix` — Homebrew casks and formulae

### Darwin Constraints

- Use `nh darwin switch .` (not `nh os switch .`).
- `launchd.user.agents` instead of `systemd.services`.
- No `fileSystems`, `boot`, or `systemd` options available.
- `pkgs.stdenv.isDarwin` for platform detection in HM modules.
- Some packages are not available on aarch64-darwin; use `lib.optionals pkgs.stdenv.isLinux` to exclude them.

---

## Host Selection in Flake

The flake uses `flake-parts` with host definitions in `flake-modules/hosts.nix`. Each host passes `hostname` as a `specialArgs` value to both NixOS/darwin and Home Manager modules. This hostname matches the keys in the `hostProfiles` attrset in `modules/home/claude-code.nix`.

To determine the current host at eval time in a module:
```nix
{ hostname, ... }: let
  isDesktop = hostname == "desktop";
  isServer = hostname == "server";
  isLaptop = hostname == "nixos-laptop";
  isMacbook = hostname == "Pedros-MacBook-Pro";
in { ... }
```
