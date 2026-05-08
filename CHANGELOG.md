# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-05-08

### Added

- Initial public release of the NixOS ops skill extracted from
  `phsb5321/NixOS` `dotfiles/nixos-ops-skill/`.
- Claude Code plugin manifest at `.claude-plugin/plugin.json`.
- `nixos-ops` skill: rebuild, rollback, generation diff, repair workflows
  for NixOS + nix-darwin hosts.
- Helper scripts (`nh`/`nixos-rebuild`/`home-manager` wrappers).
- Release-engineering template (chrome-bridge v0.1.0 baseline):
  - CI: JSON syntax validation, plugin manifest schema check,
    SKILL.md frontmatter check, `bash -n` syntax check on shell helpers,
    actionlint.
  - OSV-Scanner V2 with SARIF upload.
  - OpenSSF Scorecard with SARIF upload + branch-protection check.
  - Release pipeline: signed tarball, SLSA build provenance attestation
    (`actions/attest-build-provenance@v2`), CycloneDX 1.7 + SPDX 2.3 SBOMs,
    Sigstore-verifiable via `gh attestation verify`.
- `SECURITY.md` private vulnerability disclosure policy.
- `CODEOWNERS` pinning review to `@phsb5321`.
- All GitHub Actions pinned by full 40-char commit SHA.

[0.1.0]: https://github.com/yolo-labz/nixos-ops-skill/releases/tag/v0.1.0
