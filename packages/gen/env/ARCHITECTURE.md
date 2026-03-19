# Env Package Architecture

Generated env data now assumes direct SOPS recipients.

- `vars/*.sops.yaml` files are encrypted straight to recipient public keys.
- Group names remain useful for organization only.
- There is no generated per-group AGE private key layer.
