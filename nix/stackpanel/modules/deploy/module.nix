# ==============================================================================
# module.nix - Deploy Module Implementation
#
# Three responsibilities:
#   1. Register stackpanel.deployment.machines (Nix-only, machine definitions for
#      colmena / nixos-rebuild deployments)
#   2. Register per-app deployment extension options via appModules:
#      - deployment.backend     (from stackpanel.deployBackends)
#      - deployment.targets     (listOf str - machine names)
#      - deployment.defaultEnv  (str, default "prod")
#      - deployment.nixosModule (nullOr path - user override for NixOS module)
#      - deployment.command / resolvedCommand (explicit / provider ExecStart)
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
}@args:
let
  cfg = config.stackpanel;
  meta = import ./meta.nix;

  # Keep app options and backend IDs valid even when deploy is disabled.
  # Only enabled deploy apps contribute packages, credentials or services.
  deployApps =
    if cfg.modules.${meta.id}.enable then
      lib.filterAttrs (_: app: app.deployment.enable or false) cfg.apps
    else
      { };

  usesNixos = app: cfg.deployBackends.${app.deployment.backend}.nixosService;

  # Include an app in NixOS module generation when:
  #   - deployment.enable is true
  #   - the selected backend requests NixOS service generation
  #   - deployment.targets is non-empty (actually assigned to machines)
  # The `host` field is ignored here because an app can have both a cloud
  # host (for Alchemy/Cloudflare) and NixOS targets (for Colmena).
  nixosApps = lib.filterAttrs (_: app: usesNixos app && app.deployment.targets != [ ]) deployApps;

  # Any app with a NixOS backend configured (even without targets yet).
  # Used to gate devshell package injection so users don't get colmena/
  # nixos-anywhere unless they actually intend to do NixOS deployments.
  hasNixosBackend = lib.any usesNixos (lib.attrValues deployApps);

  # Any app whose deploy backend is Alchemy. Used to gate the deploy-time env
  # registry below so e.g. `NEON_API_KEY` only shows up as a missing-required
  # warning in projects that actually use Alchemy.
  hasAlchemyBackend = lib.any (app: app.deployment.backend == "alchemy") (lib.attrValues deployApps);

  # Any app that targets Cloudflare (Workers / Pages / DNS) for hosting.
  # Drives the CF API token + account-id deploy-env declarations.
  hasCloudflareHost = lib.any (
    app: lib.defaultTo cfg.deployment.defaultHost app.deployment.host == "cloudflare"
  ) (lib.attrValues deployApps);
in
{
  config.stackpanel.modules.${meta.id} = {
    enable = lib.mkDefault (cfg.enable && cfg.deployment.enable);
    enablePath = "deployment.enable";
    configPath = "deployment";
    meta = {
      inherit (meta)
        name
        description
        icon
        category
        author
        version
        homepage
        ;
    };
    source.type = "builtin";
    inherit (meta)
      features
      requires
      conflicts
      tags
      priority
      ;
  };

  # These backends are implemented by the core deployment tooling. Hosted
  # providers register alongside their integrations, not in this module.
  config.stackpanel.deployBackends = {
    colmena = {
      label = "Colmena";
      module = "colmena";
      nixosService = true;
    };
    nixos-rebuild = {
      label = "nixos-rebuild";
      module = meta.id;
      nixosService = true;
    };
    custom = {
      label = "Custom command";
      module = meta.id;
    };
  };

  # ===========================================================================
  # Per-app deployment extension options (via appModules)
  # ===========================================================================
  config.stackpanel.appModules = [
    (
      { lib, ... }:
      {
        options.deployment = {
          backend = lib.mkOption {
            type = lib.types.enum (builtins.attrNames cfg.deployBackends);
            default = "colmena";
            description = ''
              ID from stackpanel.deployBackends. Backends with nixosService
              enabled generate NixOS services for apps assigned to machines.
            '';
            example = "alchemy";
          };

          targets = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              Machine names (from stackpanel.deployment.machines) to deploy
              this app to. Used when the selected backend enables nixosService.

              Leave empty while configuring cloud-only backends or before a
              machine inventory exists.
            '';
            example = [ "prod-server" ];
          };

          defaultEnv = lib.mkOption {
            type = lib.types.str;
            default = "prod";
            description = ''
              Default environment name for deployment.
              Used to look up secrets at .stack/secrets/<env>.yaml.

              Common values: `prod`, `staging`, `preview`.
            '';
            example = "staging";
          };

          nixosModule = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = ''
              Path to a custom NixOS module for this app.
              If null, the default nixos-service.nix template is used,
              which generates a systemd service and system user.

              Use when the service needs custom systemd, sockets, users, or
              integration with host-level NixOS services.
            '';
            example = lib.literalExpression "./nixos/my-app-service.nix";
          };

          command = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              Explicit systemd ExecStart, overriding the runtime provider's
              resolvedCommand when using the generated NixOS service.
            '';
            example = "/run/current-system/sw/bin/my-app serve --port 3000";
          };

          resolvedCommand = lib.mkOption {
            type = lib.types.nullOr (lib.types.either lib.types.str (lib.types.functionTo lib.types.str));
            default = null;
            description = ''
              Default systemd ExecStart supplied by a runtime module. A function
              receives the target NixOS module arguments (including pkgs and
              inputs), plus name, the Stackpanel app name. Use the target pkgs
              rather than capturing the development machine's packages.
            '';
            example = lib.literalExpression ''
              { pkgs, inputs, name, ... }: "''${inputs.self.packages.''${pkgs.stdenv.hostPlatform.system}.''${name}}/bin/''${name}"
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
              description = ''
                Hostname or IP address of the target machine.

                Used by colmena and nixos-rebuild as the SSH target host. Prefer
                DNS names for long-lived production machines.
              '';
              example = "192.168.1.1";
            };

            user = lib.mkOption {
              type = lib.types.str;
              default = "root";
              description = ''
                SSH user for deployment, used by colmena and nixos-rebuild.

                Defaults to `root`, the common NixOS deployment user. Use a
                dedicated deploy user only when host sudo/Nix permissions support it.
              '';
              example = "root";
            };

            sshPort = lib.mkOption {
              type = lib.types.int;
              default = 22;
              description = ''
                SSH port on the target machine.

                Used for generated SSH targets and Colmena node metadata.
              '';
              example = 22;
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

                Required for complete NixOS system evaluation unless supplied by
                another imported machine module.
              '';
              example = lib.literalExpression "./.stack/machines/prod-server/hardware-configuration.nix";
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
              example = [
                {
                  networking.firewall.allowedTCPPorts = [
                    80
                    443
                  ];
                }
              ];
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

        Keep this as deploy topology, not app runtime config. App-specific systemd
        or reverse-proxy settings belong in app deployment modules.

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

    flakeOutputs = lib.mkOption {
      type = lib.types.submodule {
        options = {
          expose = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              When true, the main project flake exposes `nixosConfigurations`
              and `colmenaHive` while the deploy module is enabled. Disabling
              `stackpanel.deployment.enable` suppresses these outputs, generated
              app services, deployment tools and deploy-time credential declarations.

              Set to false for monorepos whose deployment configs are heavy or
              internal-only (e.g. dogfooding infra). Pair with `flakeDir` pointing
              at a dedicated deploy sub-flake so `nix flake check` and registry
              tools do not evaluate full NixOS systems on every flake walk.
            '';
            example = false;
          };

          flakeDir = lib.mkOption {
            type = lib.types.str;
            default = ".";
            description = ''
              Flake directory containing `nixosConfigurations` and `colmenaHive`.
              Used by deploy tooling (`stack deploy`, `stack provision`,
              colmena wrappers) to build `--flake` references.

              When `expose = false`, set this to the deploy sub-flake path
              (e.g. `"./deploy"`). Defaults to `"."` (main flake).
            '';
            example = "./deploy";
          };
        };
      };
      default = { };
      description = ''
        Controls where NixOS deployment flake outputs are exposed and how
        deploy tooling resolves flake references.

        Use this to split heavy deployment systems into a dedicated sub-flake
        without changing app/machine declarations.
      '';
    };
  };

  # ===========================================================================
  # Inject colmena + nixos-anywhere into the devshell when any app uses a
  # NixOS deployment backend.  This ensures `stack deploy` and
  # `stack provision` work in any repo without manual configuration.
  # ===========================================================================
  config.stackpanel.modulePackages.${meta.id} =
    lib.optionals (!(args.isGlobalEval or false) && hasNixosBackend)
      [
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
        description = "Token used by Alchemy's CloudflareStateStore to encrypt/decrypt deploy state. Generated automatically by `stack alchemy:setup`.";
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
    {
      imports = [ serviceModule ] ++ extraModules;
    }
  ) nixosApps;
}
