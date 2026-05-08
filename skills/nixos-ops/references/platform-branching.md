# Platform Branching Patterns

Two distinct patterns are used in this repository for platform-conditional code, depending on whether the module is user-level (Home Manager) or system-level (NixOS/darwin).

---

## Pattern 1: Home Manager / User-Level Modules

**Location:** `modules/home/`

**Detection mechanism:** `pkgs.stdenv.isDarwin` and `pkgs.stdenv.isLinux`

Use this in Home Manager modules where `pkgs` is in scope. These modules are evaluated per-host, and `pkgs` already knows the target platform.

### Conditional packages

```nix
home.packages = with pkgs;
  [
    # Available on all platforms
    ripgrep
    fd
    jq
  ]
  ++ lib.optionals pkgs.stdenv.isLinux [
    # Linux-only packages
    wl-clipboard
    xdg-utils
  ]
  ++ lib.optionals pkgs.stdenv.isDarwin [
    # macOS-only packages
    darwin.apple_sdk.frameworks.Security
  ];
```

### Conditional strings

```nix
programs.zsh.initContent = ''
  # Common config
  export EDITOR="nvim"
'' + lib.optionalString pkgs.stdenv.isLinux ''
  # Linux-specific
  export DISPLAY="''${DISPLAY:-:0}"
'' + lib.optionalString pkgs.stdenv.isDarwin ''
  # macOS-specific
  eval "$(/opt/homebrew/bin/brew shellenv)"
'';
```

### Conditional attrsets

```nix
programs.git.extraConfig =
  {
    # Common git config
    core.editor = "nvim";
  }
  // lib.optionalAttrs pkgs.stdenv.isDarwin {
    credential.helper = "osxkeychain";
  }
  // lib.optionalAttrs pkgs.stdenv.isLinux {
    credential.helper = "libsecret";
  };
```

---

## Pattern 2: System-Level Shared Modules

**Location:** `modules/shared/`

**Detection mechanism:** `options` introspection

```nix
isNixOS = builtins.hasAttr "fileSystems" options;
isDarwin = builtins.hasAttr "launchd" options;
```

Use this in modules under `modules/shared/` that must provide different system-level implementations on NixOS vs nix-darwin. The `options` argument reflects which module system is in use.

### Structure

```nix
{
  config,
  lib,
  pkgs,
  options,
  ...
}: let
  cfg = config.modules.shared.myModule;
  isNixOS = builtins.hasAttr "fileSystems" options;
  isDarwin = builtins.hasAttr "launchd" options;
in {
  options.modules.shared.myModule = {
    enable = lib.mkEnableOption "my cross-platform module";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Shared config (both platforms)
    {
      environment.systemPackages = [pkgs.my-tool];
    }

    # NixOS: systemd services
    (lib.optionalAttrs isNixOS {
      systemd.services.my-service = {
        description = "My service";
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          ExecStart = "${pkgs.my-tool}/bin/my-tool";
        };
      };
    })

    # Darwin: launchd agents
    (lib.optionalAttrs isDarwin {
      launchd.user.agents.my-service = {
        command = "${pkgs.my-tool}/bin/my-tool";
        serviceConfig = {
          KeepAlive = true;
          RunAtLoad = true;
        };
      };
    })
  ]);
}
```

---

## Anti-Patterns

### Never use `builtins.getEnv` in module code

```nix
# BAD — fails in pure evaluation mode
let homeDir = builtins.getEnv "HOME";

# GOOD — use config or specialArgs
let homeDir = config.home.homeDirectory;
```

Pure evaluation is the default in flakes. `builtins.getEnv` returns an empty string, causing subtle breakage.

### Never use bare `if-then-else` at the top level

```nix
# BAD — both branches must type-check, and this is harder to compose
config = if pkgs.stdenv.isDarwin then {
  launchd.agents.foo = { ... };
} else {
  systemd.services.foo = { ... };
};

# GOOD — lib.mkIf with lib.mkMerge
config = lib.mkMerge [
  (lib.mkIf pkgs.stdenv.isDarwin {
    launchd.agents.foo = { ... };
  })
  (lib.mkIf pkgs.stdenv.isLinux {
    systemd.services.foo = { ... };
  })
];
```

### Both branches of `lib.mkIf` must type-check

Even when a condition is false, NixOS evaluates the structure of both branches to verify option types. Referencing options that don't exist on the current platform (e.g., `systemd.services` on darwin) will cause an eval error even inside `lib.mkIf`.

**Solution:** Use `lib.optionalAttrs` with `isNixOS`/`isDarwin` in shared modules. These return `{}` when false, which avoids referencing non-existent options entirely.

### Never mix the two patterns

- In `modules/home/`: use `pkgs.stdenv.isDarwin/isLinux`
- In `modules/shared/`: use `isNixOS = builtins.hasAttr "fileSystems" options`
- Do not use `pkgs.stdenv` checks in system-level shared modules (it works but is less precise than `options` introspection for system-level distinctions)
