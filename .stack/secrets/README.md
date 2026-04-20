# Stackpanel Secrets

This repository uses recipient-driven SOPS files in `.stack/secrets`.

- `vars/*.sops.yaml` stores encrypted values.
- `<repo-root>/.sops.yaml` is generated from `stackpanel.secrets.recipients`
  and optional `stackpanel.secrets.creation-rules`. It lives at the repo
  root so editor extensions and `sops` discover it without `--config`.
- Secrets are resolved using local key helper at shell entry.

## Recipient-driven groups

Recipients are grouped by tags and tags are matched by creation rules.
Use `secrets:show-keys` to inspect current recipient and group state.

## Files

- `<repo-root>/.sops.yaml`
- `.stack/secrets/vars/*.sops.yaml`
- `.stack/secrets/bin/rekey.sh`
- `.stack/secrets/state/manifest.json` (generated)
