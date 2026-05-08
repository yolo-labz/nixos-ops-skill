# nixos-ops-skill

NixOS operations skill for [Claude Code](https://claude.com/claude-code) — covers rebuild workflows, generation management, debugging activation failures, and cross-host deployment patterns specific to NixOS + nix-darwin flakes.

## Layout

```
.claude-plugin/plugin.json        # plugin manifest
skills/nixos-ops/
  SKILL.md                        # skill body
  scripts/                        # helper scripts invoked by the skill
  references/                     # reference docs the skill consults
```

## Triggers

The skill activates on phrases like "rebuild NixOS", "switch generation", "debug activation failure", "rollback nix", "check flake outputs". See `skills/nixos-ops/SKILL.md` frontmatter for the full description matcher.

## Consumption from Nix

```nix
fetchFromGitHub {
  owner  = "yolo-labz";
  repo   = "nixos-ops-skill";
  rev    = "v0.1.0";
  sha256 = "<nix-prefetch-github yolo-labz nixos-ops-skill --rev v0.1.0>";
}
```

Reference from `programs.claude-code.enabledPlugins`.

## Versioning

Conventional Commits + semver. Releases are signed and attested via `actions/attest-build-provenance@v2`.

## License

MIT — see [`LICENSE`](LICENSE).
