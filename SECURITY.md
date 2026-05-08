# Security Policy

## Supported Versions

Only the latest tagged release of `nixos-ops-skill` receives security updates.
Pre-release/development builds from `main` are best-effort.

| Version  | Supported          |
| -------- | ------------------ |
| latest   | :white_check_mark: |
| < latest | :x:                |

## Reporting a Vulnerability

**Please do NOT open public GitHub issues for security vulnerabilities.**

Use one of these private channels:

1. **GitHub Security Advisories (preferred)** — open a private advisory at
   https://github.com/yolo-labz/nixos-ops-skill/security/advisories/new
2. **Email** — contact the maintainer directly via the email listed on
   https://github.com/phsb5321

### What to include

- Affected version (commit SHA or release tag)
- Reproduction steps or proof-of-concept
- Impact assessment (what data/system is at risk)
- Suggested mitigation (optional)

### Response SLA

- **Acknowledgement:** within 72 hours
- **Triage + initial assessment:** within 7 days
- **Fix or mitigation:** target 30 days for high/critical, 90 days for medium/low

We will credit reporters in the release notes unless anonymity is requested.

## Verifying Releases

Every release is published with cryptographic provenance via Sigstore.
Verify a downloaded release artifact:

```bash
gh attestation verify <artifact> --repo yolo-labz/nixos-ops-skill
```

SBOMs (CycloneDX 1.7 + SPDX 2.3) are attached to each GitHub Release for
supply-chain auditing.

## Threat Model

`nixos-ops-skill` ships a Claude Code skill plus helper shell scripts that
the Claude agent may invoke during a NixOS ops session (rebuild, rollback,
diff generations). Risk surface:

- Helper scripts execute on the user's NixOS host with the user's privileges
  (including `sudo` if the agent escalates). Review any update diff before
  consuming a new release.
- Tampered release tarball (mitigated by `gh attestation verify` + Sigstore
  provenance + SHA256 pinning in downstream Nix consumers).

Out-of-scope:
- The runtime behavior of Claude Code itself or the rebuild tools (`nh`,
  `nixos-rebuild`, `home-manager`) the scripts wrap.
- Sandboxing of agent-invoked commands (caller's responsibility).
