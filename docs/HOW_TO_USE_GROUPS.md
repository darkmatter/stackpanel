# How To Use Groups

Groups are just namespaced SOPS files.

- `dev` maps to `vars/dev.sops.yaml`
- `prod` maps to `vars/prod.sops.yaml`
- `common` maps to `vars/common.sops.yaml`

All of those files are encrypted directly to the public keys resolved from Nix config.
There is no separate per-group keypair anymore.
