# ==============================================================================
# portless.nix
#
# Portless reverse proxy service module for Stackpanel.
#
# Portless replaces port numbers with stable named `.localhost` URLs,
# eliminating the need to remember arbitrary port numbers during development.
# It integrates with Step CA for automatic TLS when configured.
#
# Domain format: <app>.<project>.<tld> (e.g., web.myproject.localhost)
#
# TLS priority:
#   1. Explicit tls-cert / tls-key paths (user-provided)
#   2. Step CA device certs (when step-ca.enable = true)
#   3. Auto-generated self-signed certs (when use-https = true)
#   4. Plain HTTP (default)
#
# Commands provided:
#   portless-proxy-start  - Start the portless reverse proxy
#   portless-proxy-stop   - Stop the portless reverse proxy
#   portless-status       - List registered virtual hosts
#
# Usage:
#   stackpanel.portless = {
#     enable = true;
#     project-name = "myapp";
#     tld = "localhost";       # or "test", etc.
#     use-https = false;       # Optional: auto self-signed certs
#     auto-start = true;       # Start proxy on shell entry (default)
#   };
#
# See https://port1355.dev/ for documentation.
# ==============================================================================
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.portless;
  stepCfg = config.stackpanel.step-ca or { enable = false; };
  repoRoot = ../../..;

  # Import util for debug logging
  util = config.stackpanel.util;

  # Use fallback for standalone evaluation (docs generation, nix eval, etc.)
  dirs =
    config.stackpanel.dirs or {
      state = ".stack/profile";
      profile = ".stack/profile";
    };

  # Step CA certificate paths
  stepCertPath = "${dirs.state}/step/device-root.chain.crt";
  stepKeyPath = "${dirs.state}/step/device.key";

  # Port computation — used to generate portless-prefixed dev scripts
  portsLib = import ../lib/ports.nix { inherit lib; };
  repoKey = (config.stackpanel.apps or { }).github or "darkmatter/stackpanel";
  portsCfg = config.stackpanel.ports or { project-name = "default"; };

  # ---------------------------------------------------------------------------
  # TLS & proxy flag computation
  #
  # Flags are computed declaratively via lib.cli.toCommandLineShellGNU and
  # baked into the shell script at Nix eval time. The only runtime logic is
  # a file-existence guard for Step CA certs (which may not be provisioned yet).
  # ---------------------------------------------------------------------------
  hasExplicitCerts = cfg.tls-cert != null && cfg.tls-key != null;
  useStepCa = stepCfg.enable && !hasExplicitCerts;
  tlsEnabled = hasExplicitCerts || useStepCa || cfg.use-https;

  # Flags shared across all TLS scenarios (tld, port)
  commonFlags = {
    tld = if cfg.tld != "localhost" then cfg.tld else null;
    port = cfg.proxy-port;
  };

  # Primary flags — used when the preferred TLS source is available
  proxyFlags = lib.cli.toCommandLineShellGNU { } (
    commonFlags
    // {
      cert =
        if hasExplicitCerts then
          cfg.tls-cert
        else if useStepCa then
          stepCertPath
        else
          null;
      key =
        if hasExplicitCerts then
          cfg.tls-key
        else if useStepCa then
          stepKeyPath
        else
          null;
      https = !hasExplicitCerts && !useStepCa && cfg.use-https;
    }
  );

  # Fallback flags — used when Step CA certs don't exist on disk yet
  fallbackFlags = lib.cli.toCommandLineShellGNU { } (
    commonFlags
    // {
      https = cfg.use-https;
    }
  );

  # Whether the TLD requires sudo (non-localhost TLDs need /etc/hosts management)
  needsSudo = cfg.tld != "localhost";
  sudoPrefix = if needsSudo then "sudo " else "";

  # ---------------------------------------------------------------------------
  # Shell scripts
  # ---------------------------------------------------------------------------

  portless-proxy-start = pkgs.writeShellScriptBin "portless-proxy-start" ''
    set -euo pipefail

    ${util.log.debug "portless: starting proxy"}

    ${
      if useStepCa then
        ''
          # Step CA certs may not be provisioned yet — check at runtime
          if [ -f "${stepCertPath}" ] && [ -f "${stepKeyPath}" ]; then
            ${util.log.debug "portless: using Step CA certs"}
            ${lib.optionalString needsSudo ''echo "Portless needs sudo to manage /etc/hosts for the .${cfg.tld} TLD"''}
            ${sudoPrefix}portless proxy start ${proxyFlags} 2>/dev/null || true
          else
            ${util.log.info "portless: Step CA certs not found, falling back to ${
              if cfg.use-https then "self-signed HTTPS" else "plain HTTP"
            }"}
            ${lib.optionalString needsSudo ''echo "Portless needs sudo to manage /etc/hosts for the .${cfg.tld} TLD"''}
            ${sudoPrefix}portless proxy start ${fallbackFlags} 2>/dev/null || true
          fi
        ''
      else
        ''
          ${lib.optionalString needsSudo ''echo "Portless needs sudo to manage /etc/hosts for the .${cfg.tld} TLD"''}
          ${sudoPrefix}portless proxy start ${proxyFlags} 2>/dev/null || true
        ''
    }

    ${util.log.debug "portless: proxy start complete"}
  '';

  portless-proxy-stop = pkgs.writeShellScriptBin "portless-proxy-stop" ''
    set -euo pipefail
    ${util.log.debug "portless: stopping proxy"}
    ${lib.optionalString needsSudo ''echo "Portless needs sudo to manage /etc/hosts for the .${cfg.tld} TLD"''}
    ${sudoPrefix}portless proxy stop 2>/dev/null || true
    ${util.log.debug "portless: proxy stopped"}
  '';

  portless-status = pkgs.writeShellScriptBin "portless-status" ''
    portless list
  '';

  # ---------------------------------------------------------------------------
  # Panel helpers & package.json injection
  # ---------------------------------------------------------------------------

  appsWithDomains = lib.filterAttrs (_: app: (app.domain or null) != null) (
    config.stackpanel.apps or { }
  );

  # For each app with a domain, compute the portless-prefixed dev script and
  # the app's path so we can inject it into package.json via files.entries.
  portlessDevScripts = lib.mapAttrs (
    appName: app:
    let
      appPort = portsLib.stablePort {
        repo = repoKey;
        service = appName;
      };
      portlessName = "${app.domain}.${cfg.project-name or portsCfg.project-name}";
      portlessPrefix = "portless ${portlessName} --app-port ${toString appPort} ";
      packageJsonPath =
        if (app.path or null) != null then repoRoot + "/${app.path}/package.json" else null;
      existingPackageJson =
        if packageJsonPath != null && builtins.pathExists packageJsonPath then
          builtins.fromJSON (builtins.readFile packageJsonPath)
        else
          { };
      existingDevScript = lib.attrByPath [ "scripts" "dev" ] null existingPackageJson;
      baseDevScript =
        if existingDevScript == null then
          "bun run dev"
        else if lib.hasPrefix portlessPrefix existingDevScript then
          builtins.substring (builtins.stringLength portlessPrefix) (
            builtins.stringLength existingDevScript - builtins.stringLength portlessPrefix
          ) existingDevScript
        else
          existingDevScript;
    in
    {
      path = app.path or null;
      packageJson = existingPackageJson;
      devScript = "${portlessPrefix}${baseDevScript}";
    }
  ) appsWithDomains;
  domainCount = lib.length (lib.attrNames appsWithDomains);

  tlsStatusLabel =
    if hasExplicitCerts then
      "Enabled (Custom Certs)"
    else if useStepCa then
      "Enabled (Step CA)"
    else if cfg.use-https then
      "Enabled (Self-Signed)"
    else
      "Disabled";
in
{
  config = lib.mkIf cfg.enable {
    # -------------------------------------------------------------------------
    # package.json dev script injection
    #
    # For each app with a domain, deep-merge a package.json fragment that
    # prefixes the dev script with `portless <name> --app-port <port>`.
    # This ensures `turbo run dev` (and direct `bun run dev`) routes through
    # the proxy and gets a stable URL.
    #
    # Uses the files system's JSON deep-merge (type = "json") so the fragment
    # is merged with any existing or Nix-generated package.json content.
    # -------------------------------------------------------------------------
    stackpanel.files.entries = lib.mkMerge (
      lib.mapAttrsToList (
        appName: portlessApp:
        lib.optionalAttrs (portlessApp.path != null) {
          "${portlessApp.path}/package.json" = {
            type = "json";
            source = "portless";
            description = "Portless dev script prefix for ${appName}";
            jsonValue = lib.recursiveUpdate portlessApp.packageJson {
              scripts.dev = portlessApp.devScript;
            };
          };
        }
      ) portlessDevScripts
    );

    # -------------------------------------------------------------------------
    # Devshell packages
    # -------------------------------------------------------------------------
    stackpanel.devshell.packages = [
      portless-proxy-start
      portless-proxy-stop
      portless-status
      # NOTE: The `portless` CLI itself must be available on $PATH.
      # It is not yet packaged in nixpkgs. Users should install it via
      # npm (`npm i -g portless`) or add it to their project's package.json.
      # See https://port1355.dev/ for installation instructions.
    ];

    # -------------------------------------------------------------------------
    # Auto-start hook
    # -------------------------------------------------------------------------
    stackpanel.devshell.hooks.after = lib.mkIf cfg.auto-start [
      ''
        # Start Portless proxy if not already running
        if ! portless proxy status >/dev/null 2>&1; then
          ${util.log.debug "portless: not running, starting..."}
          ${portless-proxy-start}/bin/portless-proxy-start
          ${util.log.debug "portless: started"}
        else
          ${util.log.debug "portless: already running"}
        fi
      ''
    ];

    # -------------------------------------------------------------------------
    # UI Panels
    # -------------------------------------------------------------------------

    stackpanel.panels.portless-status = {
      module = "portless";
      title = "Portless Reverse Proxy";
      icon = "server";
      type = "PANEL_TYPE_STATUS";
      order = 20;
      fields = [
        {
          name = "metrics";
          type = "FIELD_TYPE_STRING";
          value = builtins.toJSON [
            {
              label = "Project";
              value = cfg.project-name;
              status = "ok";
            }
            {
              label = "TLD";
              value = cfg.tld;
              status = "ok";
            }
            {
              label = "TLS";
              value = tlsStatusLabel;
              status = if tlsEnabled then "ok" else "warning";
            }
            {
              label = "Virtual Hosts";
              value = toString domainCount;
              status = "ok";
            }
          ];
        }
      ];
    };

    stackpanel.panels.portless-apps = {
      module = "portless";
      title = "Virtual Hosts";
      icon = "network";
      type = "PANEL_TYPE_APPS_GRID";
      order = 21;
      fields = [
        {
          name = "columns";
          type = "FIELD_TYPE_COLUMNS";
          value = builtins.toJSON [
            "name"
            "domain"
          ];
        }
      ];
      apps = lib.mapAttrs (_name: app: {
        enabled = true;
        config = {
          domain = app.domain or "";
          url = app.url or "";
          tls = if tlsEnabled then "true" else "false";
        };
      }) appsWithDomains;
    };
  };
}
