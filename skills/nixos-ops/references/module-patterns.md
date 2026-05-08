# Module Patterns

Three module archetypes used in this repository. Choose the correct one based on where the module lives and what it configures.

---

## Archetype 1: NixOS-Only Module

**Location:** `modules/services/`, `modules/core/`, `modules/gaming/`, `modules/desktop/`, `modules/hardware/`, `modules/networking/`, `modules/virtualization/`, `modules/packages/`

**Namespace:** `modules.<category>.<name>`

**When to use:** System-level configuration that only applies to NixOS hosts (systemd services, kernel parameters, NixOS-specific hardware config).

### Template

```nix
# modules/services/<name>.nix
# <Short description of what this module does>
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.services.<name>;
in {
  options.modules.services.<name> = {
    enable = lib.mkEnableOption "<human-readable description>";

    # Add module-specific options here
    someOption = lib.mkOption {
      type = lib.types.str;
      default = "value";
      description = "Description of this option";
    };
  };

  config = lib.mkIf cfg.enable {
    # NixOS configuration goes here
    environment.systemPackages = [pkgs.some-package];

    systemd.services.<name> = {
      description = "<Service description>";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.some-package}/bin/some-binary";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };
  };
}
```

### Real Example: modules/services/backup.nix

This module configures automated encrypted backups to AWS S3 using restic:

```nix
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.services.backup;
in {
  options.modules.services.backup = {
    enable = lib.mkEnableOption "automated S3 backups via restic";

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Directories to back up";
    };

    s3Bucket = lib.mkOption {
      type = lib.types.str;
      description = "S3 bucket name for backup storage";
    };

    retention = {
      keepDaily = lib.mkOption {
        type = lib.types.int;
        default = 7;
        description = "Number of daily snapshots to keep";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [pkgs.restic];

    services.restic.backups.s3-daily = {
      initialize = true;
      passwordFile = cfg.passwordFile;
      environmentFile = cfg.awsCredentialsFile;
      repository = "s3:s3.${cfg.s3Region}.amazonaws.com/${cfg.s3Bucket}";
      paths = cfg.paths;
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
      };
    };

    systemd.services.restic-backups-s3-daily.serviceConfig = {
      IOSchedulingClass = "idle";
      Nice = 19;
    };
  };
}
```

Key patterns:
- `let cfg = config.modules.services.backup;` at the top for clean references.
- `lib.mkIf cfg.enable { ... }` wrapping all config.
- Systemd service hardening: `IOSchedulingClass`, `Nice`.
- Timer with `Persistent = true` to catch up after missed runs.

---

## Archetype 2: Cross-Platform Shared Module

**Location:** `modules/shared/`

**Namespace:** `modules.shared.<name>`

**When to use:** System-level configuration that must work on both NixOS and nix-darwin. Uses platform detection to provide different implementations per platform.

### Template

```nix
# modules/shared/<name>.nix
# Cross-platform <description>
# NixOS: systemd service | macOS: launchd agent
{
  config,
  lib,
  pkgs,
  options,
  ...
}: let
  cfg = config.modules.shared.<name>;
  isNixOS = builtins.hasAttr "fileSystems" options;
  isDarwin = builtins.hasAttr "launchd" options;
in {
  options.modules.shared.<name> = {
    enable = lib.mkEnableOption "<description>";

    someOption = lib.mkOption {
      type = lib.types.str;
      description = "Shared option used on both platforms";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Both platforms: shared config
    {
      environment.systemPackages = [pkgs.some-package];
    }

    # NixOS-specific implementation
    (lib.optionalAttrs isNixOS {
      systemd.services.<name> = {
        description = "<Service description>";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.some-package}/bin/binary";
          Restart = "on-failure";
        };
      };
    })

    # Darwin-specific implementation
    (lib.optionalAttrs isDarwin {
      launchd.user.agents.<name> = {
        command = "${pkgs.some-package}/bin/binary";
        serviceConfig = {
          KeepAlive = true;
          RunAtLoad = true;
          ProcessType = "Background";
        };
      };
    })
  ]);
}
```

### Real Example: modules/shared/rclone-mount.nix

This module mounts Google Drive via rclone on both NixOS (systemd + FUSE) and macOS (launchd + macFUSE):

```nix
{
  config,
  lib,
  pkgs,
  options,
  ...
}: let
  cfg = config.modules.shared.rcloneMount;
  isNixOS = builtins.hasAttr "fileSystems" options;
  isDarwin = builtins.hasAttr "launchd" options;
in {
  options.modules.shared.rcloneMount = {
    enable = lib.mkEnableOption "cloud storage mount via rclone";

    remote = lib.mkOption {
      type = lib.types.str;
      default = "gdrive";
      description = "Name of the rclone remote";
    };

    syncs = lib.mkOption {
      type = lib.types.attrsOf syncType;
      default = {};
      description = "Periodic folder syncs between local and remote";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    { environment.systemPackages = [pkgs.rclone]; }

    (lib.optionalAttrs isNixOS {
      programs.fuse.userAllowOther = true;
      systemd.services.rclone-mount = { ... };
    })

    (lib.optionalAttrs isDarwin {
      launchd.user.agents.rclone-mount = { ... };
    })
  ]);
}
```

Key patterns:
- Platform detection via `options` introspection, NOT `pkgs.stdenv` (system-level modules do not have `pkgs.stdenv` in scope the same way).
- `lib.mkMerge` with `lib.optionalAttrs` for platform-specific blocks.
- `lib.types.attrsOf (lib.types.submodule { ... })` for complex nested config.
- Separate systemd services/timers vs launchd agents for the same logical operation.

---

## Archetype 3: Home Manager Module

**Location:** `modules/home/`

**Namespace:** Uses Home Manager's `programs.*`, `home.*`, `services.*` options directly.

**When to use:** User-level configuration (shell, editor, packages, dotfiles, development tools). Shared across all hosts that have Home Manager enabled.

**Critical constraint:** The server host does NOT use Home Manager. Never add server-specific config to `modules/home/`.

### Template

```nix
# modules/home/<name>.nix
# <Description of user-level config>
{
  config,
  pkgs,
  lib,
  hostname,
  ...
}: let
  homeDir = config.home.homeDirectory;
in {
  programs.<name> = {
    enable = true;
    # Program-specific options from Home Manager
  };

  # Platform-conditional packages
  home.packages = with pkgs;
    [
      # Packages for all platforms
      common-tool
    ]
    ++ lib.optionals pkgs.stdenv.isLinux [
      linux-specific-tool
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [
      darwin-specific-tool
    ];

  # Dotfile management
  home.file.".config/tool/config.toml".source = ../../dotfiles/tool-config.toml;

  # Or generate config inline
  home.file.".config/tool/settings.json".text = builtins.toJSON {
    setting = "value";
  };
}
```

### Real Example: modules/home/shell.nix

This module configures Zsh with Powerlevel10k, oh-my-zsh, and host-aware aliases:

```nix
{
  config,
  pkgs,
  lib,
  hostname,
  ...
}: let
  homeDir = config.home.homeDirectory;
in {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion = {
      enable = true;
      highlight = "fg=#6c7086,bold";
      strategy = ["history" "completion"];
    };
    syntaxHighlighting.enable = true;

    shellAliases = {
      ll = "ls -alF";
      gs = "git status";
      nixswitch = "${homeDir}/NixOS/user-scripts/nixswitch";
    };
  };

  home.file.".p10k.zsh".source = ../../dotfiles/dot_p10k.zsh;

  home.packages = with pkgs; [
    zsh-powerlevel10k
  ];
}
```

Key patterns:
- Uses `config.home.homeDirectory` instead of hardcoded paths.
- `hostname` is available as a specialArg for host-conditional logic.
- Platform branching uses `pkgs.stdenv.isDarwin` / `pkgs.stdenv.isLinux`.
- Dotfiles referenced via relative path to `../../dotfiles/`.
- No `options` block needed when using existing Home Manager programs.

---

## Registration

After creating a module, register it so it gets imported:

1. **NixOS modules** (`modules/services/`, `modules/core/`, etc.): Add to the category's import list or the host's `configuration.nix`.
2. **Shared modules** (`modules/shared/`): Add to the shared imports in the flake or host configs that need it.
3. **Home Manager modules** (`modules/home/`): Add to the Home Manager imports. Ensure it is NOT imported for the server host.
4. **Profile activation**: If the module has an `enable` option, set it in the appropriate profile (`profiles/desktop.nix`, `profiles/server.nix`, etc.).
