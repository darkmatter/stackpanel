# Stack Secrets

Stackpanel secrets rely on Nix-configured SOPS recipients and explicit creation rules.

- Recipients live in `stackpanel.secrets.recipients` with a fallback from `stackpanel.users`.
- Recipient groups live in `stackpanel.secrets.recipient-groups`.
- `<repo-root>/.sops.yaml` is generated from recipients, recipient groups, and `stackpanel.secrets.creation-rules`. It lives at the repo root so `sops` and editor extensions discover it without `--config`.
- Variable values live in `.stack/secrets/vars/<group>.sops.yaml`, where `<group>` comes from variable IDs such as `/dev/DATABASE_URL` or `/prod/API_KEY`.
- There is no extra per-group private key layer in the secrets flow.
- `sops-age-keys` supports configurable ordered key discovery through
  `stackpanel.secrets.sops-age-keys.sources`.
- Supported source types include user paths, repo paths, macOS Keychain, 1Password refs, vals refs, and scripts.
- Legacy compatibility fields `user-key-path`, `repo-key-path`, `paths`, and
  `op-refs` still exist, but `sources` is the preferred model.
- `stackpanel.secrets.master-keys` remains for legacy `.age`/vals consumers such as wrapped packages and `secrets:export`; it is separate from SOPS recipients.

Example:

```nix
{
  stackpanel.secrets = {
    recipients = {
      alice = {
        public-key = "age1alicepublickeyexample000000000000000000000000000000";
        tags = [ "dev" "prod" ];
      };
      deploy_bot = {
        public-key = "age1deploypublickeyexample0000000000000000000000000000";
        tags = [ "prod" "ci" ];
      };
    };

    recipient-groups = {
      dev-team.recipients = [ "alice" ];
      prod-admins.recipients = [ "alice" "deploy_bot" ];
    };

    creation-rules = [
      {
        path-regex = "^\\.stack/secrets/vars/dev\\.sops\\.yaml$";
        recipient-groups = [ "dev-team" ];
      }
      {
        path-regex = "^\\.stack/secrets/vars/prod\\.sops\\.yaml$";
        recipient-groups = [ "prod-admins" ];
      }
    ];
  };

  stackpanel.variables = {
    "/dev/DATABASE_URL" = { };
    "/prod/DATABASE_URL" = { };
  };
}
```
