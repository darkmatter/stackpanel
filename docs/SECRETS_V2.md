# Secrets V2

The current model is simpler than the original V2 draft:

- SOPS files in `vars/` are encrypted directly to recipient public keys.
- `stack.secrets.recipients` and `stack.users` define recipient public keys.
- `.stack/secrets/.sops.yaml` is generated from those recipients and their tags.
- `rekey.sh` updates `vars/*.sops.yaml` when the recipient set changes.
- Intermediate group key files like `dev.age` and `dev.enc.age` are gone.
- Private key lookup for decrypting SOPS files is centralized in `sops-age-keys`,
  and can be extended via:
- `stack.secrets.sops-age-keys.sources`
- legacy compatibility fields like `paths` / `op-refs` still exist
- preferred source list entries can include macOS Keychain, 1Password refs, vals refs, and scripts
