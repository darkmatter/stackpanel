# Stackpanel Secrets

Stackpanel secrets now rely on Nix-configured SOPS recipients and explicit creation rules.

- Recipients live in `stackpanel.secrets.recipients` (with a fallback from `stackpanel.users`).
- Recipient groups live in `stackpanel.secrets.recipient-groups`.
- `.stack/secrets/.sops.yaml` is generated from recipients, recipient groups, and `stackpanel.secrets.creation-rules`.
- There is no extra per-group private key layer in the secrets flow.
- `sops-age-keys` supports configurable ordered key discovery through
  `stackpanel.secrets.sops-age-keys.sources`.
- Supported source types include user paths, repo paths, macOS Keychain, 1Password refs, vals refs, and scripts.
- Legacy compatibility fields `user-key-path`, `repo-key-path`, `paths`, and
  `op-refs` still exist, but `sources` is the preferred model.
