# ==============================================================================
# module.nix - Deploy Module Implementation
#
# Three responsibilities:
#   1. Register stackpanel.deployment.machines (Nix-only, machine definitions for
#      colmena / nixos-rebuild deployments)
#   2. Register per-app deployment extension options via appModules:
#      - deployment.backend     (enum: colmena/nixos-rebuild/alchemy/fly/custom)
#      - deployment.targets     (listOf str - machine names)
#      - deployment.defaultEnv  (str, default "prod")
#      - deployment.nixosModule (nullOr path - user override for NixOS module)
#      - deployment.command     (nullOr str - ExecStart for non-Go apps)
#   3. Compute stackpanel.nixosModules by importing nixos-service.nix (or the
#      user-provided nixosModule) for each app with a NixOS backend.
#
# NOTE: deployment.enable and deployment.host are defined in core/options/apps.nix.
#       This module extends (not replaces) those options.
#
# NOTE: Language modules cannot write to stackpanel.apps (infinite recursion).
#       The appModules pattern is the correct way to extend per-app options.
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel;

  nixosBackends = [
    "colmena"
    "nixos-rebuild"
  ];

  cloudPlatforms = [
    "cloudflare"
    "fly"
  ];

  # Include an app in NixOS module generation when:
  #   - deployment.enable is true
  #   - deployment.backend is a NixOS backend (colmena or nixos-rebuild)
  #   - deployment.targets is non-empty (actually assigned to machines)
  # The `host` field is ignored here because an app can have both a cloud
  # host (for Alchemy/Cloudflare) and NixOS targets (for Colmena).
  nixosApps = lib.filterAttrs (
    _: app:
    (app.deployment.enable or false)
    && builtins.elem (app.deployment.backend or "colmena") nixosBackends
    && (app.deployment.targets or []) != []
  ) cfg.apps;

  # Any app with a NixOS backend configured (even without targets yet).
  # Used to gate devshell package injection so users don't get colmena/
  # nixos-anywhere unless they actually intend to do NixOS deployments.
  hasNixosBackend = lib.any (
    app:
    (app.deployment.enable or false)
    && builtins.elem (app.deployment.backend or "colmena") nixosBackends
  ) (lib.attrValues cfg.apps);

  # Any app whose deploy backend is Alchemy. Used to gate the deploy-time env
  # registry below so e.g. `NEON_API_KEY` only shows up as a missing-required
  # warning in projects that actually use Alchemy.
  hasAlchemyBackend = lib.any (
    app:
    (app.deployment.enable or false)
    && (app.deployment.backend or "colmena") == "alchemy"
  ) (lib.attrValues cfg.apps);

  # Any app that targets Cloudflare (Workers / Pages / DNS) for hosting.
  # Drives the CF API token + account-id deploy-env declarations.
  hasCloudflareHost = lib.any (
    app:
    (app.deployment.enable or false)
    && (app.deployment.host or null) == "cloudflare"
  ) (lib.attrValues cfg.apps);
in
{
  # ===========================================================================
  # Per-app deployment extension options (via appModules)
  # ===========================================================================
  config.stackpanel.appModules = [
    (
      { lib, ... }:
      {
        options.deployment = {
          backend = lib.mkOption {
            type = lib.types.enum [
              "colmena"
              "nixos-rebuild"
              "alchemy"
              "fly"
              "custom"
            ];
            default = "colmena";
            description = ''
              Deployment backend to use for this app.

                colmena       - NixOS via colmena (multi-host, recommended)
                nixos-rebuild - NixOS via nixos-rebuild switch (single-host)
                alchemy       - Cloudflare Workers via Alchemy
                fly           - Fly.io containers
                custom        - Custom deploy command
            '';
          };

          targets = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              Machine names (from stackpanel.deployment.machines) to deploy
              this app to. Only used for colmena and nixos-rebuild backends.
            '';
            example = [ "prod-server" ];
          };

          defaultEnv = lib.mkOption {
            type = lib.types.str;
            default = "prod";
            description = ''
              Default environment name for deployment.
              Used to look up secrets at .stack/secrets/<env>.yaml.
            '';
          };

          nixosModule = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = ''
              Path to a custom NixOS module for this app.
              If null, the default nixos-service.nix template is used,
              which generates a systemd service and system user.
            '';
          };

          command = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              ExecStart command for the systemd service.
              Required for non-Go apps when backend is colmena or nixos-rebuild.
              Go apps derive the command from their built package automatically.
            '';
          };

          modules = lib.mkOption {
            type = lib.types.listOf lib.types.deferredModule;
            default = [ ];
            description = ''
              Additional NixOS modules included alongside this app's generated
              service module on every target machine.

              Use for app-specific NixOS config: firewall ports, nginx reverse
              proxy, database permissions, etc.
            '';
            example = lib.literalExpression ''
              [
                {
                  networking.firewall.allowedTCPPorts = [ 3000 ];
                  services.nginx.virtualHosts."example.com" = {
                    locations."/" = { proxyPass = "http://127.0.0.1:3000"; };
                  };
                }
              ]
            '';
          };
        };
      }
    )
  ];

  # ===========================================================================
  # stackpanel.deployment.machines - machine definitions (Nix-only)
  # ===========================================================================
  options.stackpanel.deployment = {
    machines = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            host = lib.mkOption {
              type = lib.types.str;
              description = "Hostname or IP address of the target machine.";
              example = "192.168.1.1";
            };

            user = lib.mkOption {
              type = lib.types.str;
              default = "root";
              description = "SSH user for deployment (used by colmena and nixos-rebuild).";
            };

            sshPort = lib.mkOption {
              type = lib.types.int;
              default = 22;
              description = "SSH port on the target machine.";
            };

            proxyJump = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                SSH ProxyJump host for reaching machines behind NAT or on private
                networks. The value is passed as-is to ssh -J and to colmena's
                deployment.targetHost via an SSH config block.

                Common use case: VMs on a private bridge that are only reachable
                through a hypervisor host.
              '';
              example = "root@hypervisor.example.com";
            };

            system = lib.mkOption {
              type = lib.types.str;
              default = "x86_64-linux";
              description = "NixOS system architecture.";
              example = "x86_64-linux";
            };

            hardwareConfig = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = ''
                Path to hardware-configuration.nix for this machine.
                Generated by nixos-generate-config or nixos-anywhere.
              '';
            };

            diskLayout = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = ''
                Path to a disko Nix file declaring the disk partition layout.
                Required for bare-metal provisioning where you control partitioning.
                If null, nixos-anywhere runs with --no-reformat (assumes an existing
                partition layout, e.g. a cloud VPS rescue environment).
                See: https://github.com/nix-community/disko
              '';
              example = lib.literalExpression "./.stack/machines/prod-server/disks.nix";
            };

            modules = lib.mkOption {
              type = lib.types.listOf lib.types.deferredModule;
              default = [ ];
              description = ''
                Additional NixOS modules to include in this machine's configuration.
                Use for arbitrary NixOS config (firewall, extra services, etc.).
                SSH keys can also go here, but prefer authorizedKeys for discoverability.
              '';
              example = [ { networking.firewall.allowedTCPPorts = [ 80 443 ]; } ];
            };

            authorizedKeys = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = ''
                SSH public keys authorized to connect to this machine as the deployment
                user (see user, default "root"). Written to
                users.users.<user>.openssh.authorizedKeys.keys in the NixOS config.

                These are plain public key strings -- safe to commit to the repo.
              '';
              example = [
                "ssh-ed25519 AAAA... alice@laptop"
                "ssh-ed25519 AAAA... ci-runner"
              ];
            };
          };
        }
      );
      default = { };
      description = ''
        Machine definitions for NixOS deployments (colmena / nixos-rebuild).

        Each entry defines a target server. Apps reference machines via
        deployment.targets = [ "machine-name" ].

        Example:
          stackpanel.deployment.machines = {
            prod-server = {
              host = "192.168.1.10";
              user = "root";
              system = "x86_64-linux";
              hardwareConfig = ./hardware/prod-server.nix;
            };
          };
      '';
    };
  };

  # ===========================================================================
  # Inject colmena + nixos-anywhere into the devshell when any app uses a
  # NixOS deployment backend.  This ensures `stackpanel deploy` and
  # `stackpanel provision` work in any repo without manual configuration.
  # ===========================================================================
  config.stackpanel.devshell.packages = lib.optionals hasNixosBackend [
    pkgs.colmena
    pkgs.nixos-anywhere
  ];

  # ===========================================================================
  # Cross-cutting deploy-time env registry — `stackpanel.envs.deploy`.
  #
  # Variables here are consumed by `loadEnvScope("deploy")` from the deploy
  # entrypoints (apps/*/alchemy.run.ts via `packages/infra/src/lib/deploy.ts`)
  # rather than being copied into every app's `apps.<app>.env`. This is the
  # canonical example of "modules contributing envs they need": the deploy
  # module knows which credentials are required to actually deploy and
  # registers them in one place, conditionally on detected app targets.
  #
  # Only declared when at least one app has the relevant backend / host
  # configured, so projects that don't deploy via Alchemy / Cloudflare don't
  # see spurious "missing required" warnings.
  # ===========================================================================
  config.stackpanel.envs.deploy = lib.mkMerge [
    (lib.mkIf hasCloudflareHost {
      CLOUDFLARE_ACCOUNT_ID = {
        sops = "/shared/cloudflare-account-id";
        required = true;
        description = "Cloudflare account ID that owns the Workers/Pages/DNS resources we deploy. Find it at https://dash.cloudflare.com (right sidebar of any zone).";
      };
      CLOUDFLARE_API_TOKEN = {
        sops = "/shared/cloudflare-api-token";
        required = true;
        description = "Cloudflare API token with Workers Scripts:Edit + Workers Routes:Edit. Create one at https://dash.cloudflare.com/profile/api-tokens.";
      };
    })
    (lib.mkIf hasAlchemyBackend {
      NEON_API_KEY = {
        sops = "/shared/neon-api-key";
        required = true;
        description = "Neon API key used by alchemy to provision Postgres projects. Create one at https://console.neon.tech/app/settings/api-keys.";
      };
      ALCHEMY_STATE_TOKEN = {
        sops = "/common/alchemy-state-token";
        required = true;
        description = "Token used by Alchemy's CloudflareStateStore to encrypt/decrypt deploy state. Generated automatically by `sp alchemy:setup`.";
      };
    })
  ];

  # ===========================================================================
  # Compute stackpanel.nixosModules from apps with NixOS backends
  # ===========================================================================
  config.stackpanel.nixosModules = lib.mapAttrs (
    name: app:
    let
      serviceModule =
        if app.deployment.nixosModule != null then
          import app.deployment.nixosModule
        else
          import ./nixos-service.nix { inherit name app lib; };
      extraModules = app.deployment.modules;
    in
    { imports = [ serviceModule ] ++ extraModules; }
  ) nixosApps;
}
