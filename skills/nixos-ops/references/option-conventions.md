# Option Conventions

Naming, typing, and formatting conventions observed in this repository for NixOS module options.

---

## Formatting

All `.nix` files use **alejandra** formatting:
- 2-space indentation (no tabs)
- Trailing commas in function arguments
- Consistent brace/bracket placement
- Run `alejandra` before committing changes

```nix
# Correct: alejandra style
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.services.myService;
in {
  # ...
}
```

---

## Enable Option

Every module that can be toggled MUST have an enable option using `lib.mkEnableOption`:

```nix
options.modules.services.myService = {
  enable = lib.mkEnableOption "short description of the service";
};
```

This creates a `lib.types.bool` option defaulting to `false` with a description prefixed by "Whether to enable".

---

## Option Types

Use explicit `lib.` prefixes for all type references:

```nix
# Strings
lib.mkOption {
  type = lib.types.str;
  default = "value";
  description = "A string option";
}

# Integers
lib.mkOption {
  type = lib.types.int;
  default = 42;
  description = "An integer option";
}

# Booleans (when not using mkEnableOption)
lib.mkOption {
  type = lib.types.bool;
  default = true;
  description = "A boolean option";
}

# Lists
lib.mkOption {
  type = lib.types.listOf lib.types.str;
  default = [];
  description = "A list of strings";
}

# Packages
lib.mkOption {
  type = lib.types.listOf lib.types.package;
  default = with pkgs; [some-package];
  description = "Packages to install";
}

# Enums
lib.mkOption {
  type = lib.types.enum ["push" "pull"];
  description = "Sync direction";
}

# Attribute sets
lib.mkOption {
  type = lib.types.attrsOf lib.types.str;
  default = {};
  description = "Key-value string pairs";
}

# Complex nested config (submodule)
lib.mkOption {
  type = lib.types.attrsOf (lib.types.submodule {
    options = {
      localPath = lib.mkOption {
        type = lib.types.str;
        description = "Local path";
      };
      remotePath = lib.mkOption {
        type = lib.types.str;
        description = "Remote path";
      };
    };
  });
  default = {};
  description = "Named sync entries";
}
```

---

## Priority and Override

### `lib.mkDefault` — Profile-level defaults

Use in `profiles/` to set sensible defaults that hosts can override:

```nix
# profiles/desktop.nix
modules.services.printing.enable = lib.mkDefault true;
modules.desktop.gnome.enable = lib.mkDefault true;
```

### `lib.mkForce` — Host-level overrides

Use in `hosts/` when a host must override a profile default:

```nix
# hosts/server/configuration.nix
qt.enable = lib.mkForce false;  # Override profile that enables Qt
```

### Priority order (lowest number = highest priority)

1. `lib.mkOverride 10` (or `lib.mkForce`) — strongest override
2. `lib.mkOverride 50` — explicit host config
3. `lib.mkDefault` (= `lib.mkOverride 1000`) — profile defaults
4. Option `default` value (= `lib.mkOverride 1500`) — weakest

---

## Explicit `lib.` Prefixes

Never use `with lib;` in new code. Always use explicit prefixes:

```nix
# BAD
with lib; {
  options = {
    enable = mkEnableOption "foo";
    name = mkOption { type = types.str; };
  };
  config = mkIf cfg.enable { ... };
}

# GOOD
{
  options = {
    enable = lib.mkEnableOption "foo";
    name = lib.mkOption { type = lib.types.str; };
  };
  config = lib.mkIf cfg.enable { ... };
}
```

**Note:** Some existing modules (like `modules/services/printing.nix`) still use `with lib;`. New code must use explicit prefixes. Existing modules should be migrated when touched for other changes.

---

## Config Block Pattern

Always wrap module config in `lib.mkIf cfg.enable`:

```nix
let
  cfg = config.modules.services.myService;
in {
  options.modules.services.myService = {
    enable = lib.mkEnableOption "my service";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port to listen on";
    };
  };

  config = lib.mkIf cfg.enable {
    # All configuration guarded behind enable flag
    networking.firewall.allowedTCPPorts = [cfg.port];
  };
}
```

---

## Description Strings

- Always provide a `description` for every option.
- Keep descriptions concise and action-oriented.
- Do not include the option name in the description (it is already shown).
- Use backticks for inline code references in descriptions.

```nix
# GOOD
description = "S3 bucket name for backup storage";
description = "Extra arguments to pass to rclone mount";

# BAD
description = "The s3Bucket option sets the S3 bucket name";
description = "";  # Never leave empty
```
