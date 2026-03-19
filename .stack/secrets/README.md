# Stackpanel Secrets

This repository uses recipient-driven SOPS files in `.stack/secrets`.

- `vars/*.sops.yaml` stores encrypted values.
- `.sops.yaml` is generated from `stackpanel.secrets.recipients` and
  optional `stackpanel.secrets.creation-rules`.
- Secrets are resolved using local key helper at shell entry.

## Recipient-driven groups

Recipients are grouped by tags and tags are matched by creation rules.
Use `secrets:show-keys` to inspect current recipient and group state.

## Files

- `.stack/secrets/vars/*.sops.yaml`
- `.stack/secrets/.sops.yaml`
- `.stack/secrets/state/manifest.json` (generated)
