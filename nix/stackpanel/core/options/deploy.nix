# ==============================================================================
# deploy.nix
#
# Deploy-time options for Stackpanel — currently the alchemy state backend
# toggle. Hosted backend requires a Pro subscription on api.stackpanel.com;
# local backend preserves the filesystem default (.alchemy/state/) and
# works without network access.
#
# The toggle contributes entries to `stackpanel.envs.deploy` so the codegen
# pipeline serializes them into the deploy-scope env loader. At deploy time
# (both local and CI) those values are exported as env vars, which the
# HostedState alchemy-effect adapter in packages/infra reads.
# ==============================================================================
{ lib, config, ... }:
let
  cfg = config.stackpanel.deploy;
  hostedSelected = cfg.stateBackend == "hosted";
in
{
  options.stackpanel.deploy = {
    stateBackend = lib.mkOption {
      type = lib.types.enum [ "hosted" "local" ];
      default = "local";
      description = ''
        Which backend alchemy-effect uses for deploy state.

        - `local`: filesystem at .alchemy/state/ (default). No network,
          no account, works offline. State lives on whichever machine
          ran the deploy, so CI runners orphan resources across runs.

        - `hosted`: api.stackpanel.com stores encrypted state per
          organization. Survives runner churn, enables true team
          deploys, audited via the studio's State panel. Requires an
          active Pro subscription.
      '';
    };

    apiUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://api.stackpanel.com";
      description = ''
        Base URL of the stackpanel cloud API. Override for self-hosted
        or staging environments. The alchemy-effect adapter reads this
        from STACKPANEL_API_URL at deploy time.
      '';
    };
  };

  config.stackpanel.envs.deploy = lib.mkMerge [
    {
      # Non-secret knobs surface as literal env values — same shape whether
      # hosted or local is selected, so flipping the toggle and re-generating
      # the env package is enough to switch backends.
      STACKPANEL_STATE_BACKEND = {
        description = "Alchemy state backend — 'hosted' or 'local'.";
        value = cfg.stateBackend;
        required = false;
      };
      STACKPANEL_API_URL = {
        description = "Base URL for the stackpanel cloud API.";
        value = cfg.apiUrl;
        required = false;
      };
    }
    # ALCHEMY_STATE_TOKEN is a secret required only when hosted is selected.
    # The SOPS reference is intentionally left unset here — users supply it
    # via `.stack/secrets/vars/shared.sops.yaml` (alongside CLOUDFLARE_API_TOKEN
    # etc.) to avoid baking a specific SOPS path into core options. Marking
    # `required = true` makes preflight fail fast if the secret is missing,
    # rather than hitting a 401 on first deploy.
    (lib.mkIf hostedSelected {
      ALCHEMY_STATE_TOKEN = {
        description = ''
          Bearer token for api.stackpanel.com. Obtain via
          `stackpanel auth login` or GitHub Actions secret.
        '';
        required = true;
        secret = true;
      };
    })
  ];
}
