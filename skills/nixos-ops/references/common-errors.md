# Common Errors and Fixes

Known error patterns from this repository's history. When diagnosing a build or runtime failure, check this list first before investigating further.

---

## 1. auditd Fills Disk (289GB)

**Error pattern:**
```
No space left on device
/var/log/audit/audit.log grows to hundreds of GB
```

**Root cause:** `security.auditd.enable = true` with an execve audit rule generates massive log volume on active workstations. The audit log consumed 289GB on the desktop host (occurred twice).

**Fix:**
```nix
security.auditd.enable = false;
security.audit.enable = false;
```

**Prevention:** Run `scripts/check-disk-before-build.sh` before every build. It specifically checks `/var/log/audit/` for runaway growth.

**Source file:** `hosts/desktop/configuration.nix`

---

## 2. Plex `__isoc23_sscanf` / glibc Mismatch

**Error pattern:**
```
/nix/store/...-plex-media-server-.../lib/libgcc_s.so.1: version `GCC_7.0.0' not found
symbol lookup error: __isoc23_sscanf
```

**Root cause:** Plex runs inside an FHS sandbox (`buildFHSEnv`) that loads host GPU libraries, which may link against a different glibc version than the one in the sandbox.

**Fix:**
```nix
# Clear LD_LIBRARY_PATH before launching Plex to prevent host lib contamination
environment.systemPackages = [
  (pkgs.writeShellScriptBin "plex-clean" ''
    export LD_LIBRARY_PATH=""
    exec ${pkgs.plex}/bin/PlexMediaServer "$@"
  '')
];
```

**Source file:** `hosts/server/configuration.nix`

---

## 3. glibc 2.42 Locale-Archive Regression

**Error pattern:**
```
perl: warning: Setting locale failed.
perl: warning: Please check that your locale settings:
    LANGUAGE = (unset),
    LC_ALL = (unset),
    LC_CTYPE = "pt_BR.UTF-8",
    LANG = "en_US.UTF-8"
    are supported and installed on your system.
```

**Root cause:** `i18n.supportedLocales = ["all"]` triggers a glibc 2.42 regression where the locale archive is not properly built. Combined with Brazilian Portuguese locale vars leaking into remote sessions.

**Fix:**
```nix
i18n.supportedLocales = [
  "en_US.UTF-8/UTF-8"
  "pt_BR.UTF-8/UTF-8"
  "C.UTF-8/UTF-8"
];
# Suppress perl locale warnings in nix-shell
environment.variables.PERL_BADLANG = "0";
```

**Source file:** `modules/core/locale.nix` or host-level i18n config

---

## 4. Qt6 Build Failure on Server

**Error pattern:**
```
error: Package 'qt6-base-...' is not supported on 'x86_64-linux'
or: qt6 build timeout / OOM on low-resource VM
```

**Root cause:** The server is a Proxmox VM with limited resources. Qt6 is pulled in transitively by some packages and fails to build or takes too long. Known nixpkgs issue with Qt6 on headless systems.

**Fix:**
```nix
qt.enable = lib.mkForce false;
```

**Source file:** `hosts/server/configuration.nix`

---

## 5. `nix flake check` Fails on Darwin Inputs

**Error pattern:**
```
error: 'aarch64-darwin' is not a supported system type
error: attribute 'darwinConfigurations' not found
```

**Root cause:** Darwin modules and configurations are not evaluable on a Linux host. `nix flake check` tries to evaluate all outputs including darwin ones when run on Linux.

**Fix:** Use `--no-build` flag to skip building, and accept that cross-platform flake check will emit warnings:
```bash
nix flake check --no-build
```

This is a known limitation of multi-platform flakes. The flake evaluates successfully on each respective platform.

**Source file:** `flake.nix`

---

## 6. Kernel 6.17+ Boot Failure on Laptop

**Error pattern:**
```
nvidia: module verification failed: missing signature
BUG: kernel NULL pointer dereference
Black screen after GRUB
```

**Root cause:** NVIDIA proprietary driver is incompatible with kernel 6.17+. The laptop uses a GTX 1650 which requires the NVIDIA driver.

**Fix:**
```nix
boot.kernelPackages = pkgs.linuxPackages_6_12;
```

**Prevention:** Pin the kernel version on hosts with NVIDIA GPUs until driver compatibility is confirmed.

**Source file:** `hosts/laptop/hardware.nix` or boot configuration

---

## 7. jbd2 Blocked-Task Panic on Server

**Error pattern:**
```
INFO: task jbd2/sda1-8:XXX blocked for more than 120 seconds.
kernel: hung_task_timeout_secs
```

**Root cause:** The server runs as a Proxmox VM with HDD-backed storage. Heavy I/O operations (nix builds, large file transfers) can cause the journaling thread to block beyond the default 120-second hung task timeout.

**Fix:**
```nix
boot.kernel.sysctl."kernel.hung_task_timeout_secs" = 300;
```

**Source file:** `hosts/server/configuration.nix`

---

## 8. `command-not-found` Broken on Flakes

**Error pattern:**
```
command-not-found: command not found
DBI connect('dbname=/nix/var/nix/profiles/per-user/root/channels/nixos/programs.sqlite',...) failed
```

**Root cause:** The `command-not-found` handler relies on a channel-based SQLite database that does not exist in a flake-based NixOS installation (no channels).

**Fix:** Replace with `nix-index` and the community-maintained database:
```nix
programs.nix-index = {
  enable = true;
  enableZshIntegration = true;
};
programs.command-not-found.enable = false;
```

Add `nix-index-database` flake input for pre-built index.

**Source file:** `modules/core/nix.nix` or shell configuration

---

## 9. Infinite Recursion in Module

**Error pattern:**
```
error: infinite recursion encountered
       at /nix/store/...-source/modules/...
```

**Root cause:** Most commonly caused by:
1. Referencing `config.modules.X.something` inside the `options.modules.X` block (self-reference).
2. Circular imports: module A imports module B which imports module A.
3. Using `config` values in `default` of an option in the same module.

**Fix:**
- Move the `config` reference out of the `options` block and into the `config` block.
- Break circular imports by extracting shared logic into a third module.
- Use `lib.mkDefault` instead of reading `config` in option defaults.

**Diagnostic:** Add `--show-trace` to the nix command and look for the repeated file path in the trace output. The file that appears multiple times is the recursion source.

---

## 10. Hash Mismatch on fetchFromGitHub

**Error pattern:**
```
hash mismatch in fixed-output derivation '/nix/store/...':
  specified: sha256-AAAA...
  got:       sha256-BBBB...
```

**Root cause:** The upstream repository changed the tarball content (force-push, re-tag, or GitHub regenerated the archive). The pinned hash no longer matches.

**Fix:**
```bash
# Get the correct hash for the current content
nix-prefetch-url --unpack https://github.com/<owner>/<repo>/archive/<rev>.tar.gz
# Or use nix-prefetch-github
nix-prefetch-github <owner> <repo> --rev <rev>
```

Update the `hash` field in the `fetchFromGitHub` call with the new value.

---

## 11. Collision Between Packages

**Error pattern:**
```
error: collision between '/nix/store/...-package-A/bin/foo'
       and '/nix/store/...-package-B/bin/foo'
```

**Root cause:** Two derivations in `environment.systemPackages` or `home.packages` provide the same file path. Common with tools that bundle overlapping utilities.

**Fix:** Either:
1. Remove one of the conflicting packages.
2. Use `lib.hiPrio` to give one package priority:
   ```nix
   home.packages = [
     (lib.hiPrio pkgs.package-A)
     pkgs.package-B
   ];
   ```
3. Use overlays to patch one package's output.

---

## 12. Unfree Package Blocked

**Error pattern:**
```
error: Package 'vscode-...' in ... has an unfree license ('unfree'), refusing to evaluate.
       a]  To temporarily allow unfree packages, use: NIXPKGS_ALLOW_UNFREE=1
```

**Root cause:** The nixpkgs configuration does not have `allowUnfree` set, and a package with a non-free license is requested.

**Fix:**
```nix
# In flake.nix nixpkgs config
nixpkgs.config.allowUnfree = true;
```

Or for a single package in a dev shell:
```nix
pkgs.mkShell {
  packages = [
    (pkgs.callPackage ./my-pkg.nix { }).overrideAttrs (old: {
      meta = old.meta // { license = lib.licenses.unfree; };
    })
  ];
}
```

This repo already sets `allowUnfree = true` globally. If the error appears, check that the flake config is properly propagated to the nixpkgs instance being used.
