# ==============================================================================
# apps.nix
#
# Application port management and Caddy virtual host configuration for devenv.
#
# This module provides a unified way to manage application ports and domains.
# Each app gets a deterministic port based on project name and offset, and can
# optionally be assigned a domain with automatic Caddy vhost setup.
#
# Domain Format:
#   Virtual hosts use the format: <app>.<project>.<tld>
#   Example: web.myproject.localhost, api.myproject.lan
#   The TLD is configured via stackpanel.caddy.tld (default: "localhost")
#
# Port Layout (from basePort):
#   +0 to +9:   User apps (web, server, docs, etc.)
#   +10 to +99: Infrastructure services (postgres, redis, minio, etc.)
#
# Usage:
#   stackpanel.apps = {
#     web = {};                          # Just port (basePort + 0)
#     server = { offset = 1; };          # Port with explicit offset
#     docs = { domain = "docs"; };       # Port + docs.<project>.localhost vhost
#     api = {
#       domain = "api";
#       tls = true;                      # Use TLS (requires Step CA)
#     };
#   };
#
# Environment variables:
#   $PORT_WEB, $PORT_SERVER, etc.
#   $URL_DOCS, $URL_API (for apps with domains)
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  # Get user-defined apps (before computed values)
  rawApps = config.stackpanel.apps;
  portsCfg = config.stackpanel.ports;
  caddyCfg = config.stackpanel.caddy;

  # Domain format: <app>.<project>.<tld>
  projectName = portsCfg.project-name;
  tld = caddyCfg.tld or "localhost";

  # Import caddy library for adding sites
  caddyLib = import ../services/caddy { inherit pkgs lib; };
  stepCaCfg = config.stackpanel.step-ca or { enable = false; };
  useStepTls = caddyCfg.use-step-tls or false;
  stepEnabled = useStepTls && (stepCaCfg.enable or false);
  stepCaUrl = stepCaCfg.ca-url or "";
  stepCaRoot = "$HOME/.step/certs/root_ca.crt";
  caddyScripts = caddyLib.mkCaddyScripts {
    inherit stepEnabled;
    inherit stepCaUrl;
    stepCaFingerprint = stepCaCfg.ca-fingerprint or "";
  };

  # Apps use offset 0-9 (services use 10+)
  appsBaseOffset = 0;

  # Get the project base port
  projectBasePort = portsCfg.base-port;

  # Compute full app configurations with ports
  appNames = lib.attrNames rawApps;
  computedApps = lib.listToAttrs (
    lib.imap0 (
      idx: name:
      let
        appCfg = rawApps.${name};
        offset = if appCfg.offset != null then appCfg.offset else idx;
        port = projectBasePort + appsBaseOffset + offset;
        # Domain format: <app>.<project>.<tld> (e.g., web.myproject.localhost)
        domain = if appCfg.domain != null then "${appCfg.domain}.${projectName}.${tld}" else null;
        protocol = if appCfg.tls then "https" else "http";
        url = if domain != null then "${protocol}://${domain}" else null;
      in
      {
        inherit name;
        value = {
          inherit port domain url;
          inherit (appCfg) tls offset;
        };
      }
    ) appNames
  );

  # Generate environment variable names for apps (uppercase with PORT_ prefix)
  appEnvVars = lib.listToAttrs (
    map (
      name:
      let
        app = computedApps.${name};
      in
      {
        name = "PORT_${lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] name)}";
        value = toString app.port;
      }
    ) appNames
  );

  # Generate URL environment variables for apps with domains
  appUrlEnvVars = lib.listToAttrs (
    lib.filter (x: x.value != null) (
      map (
        name:
        let
          app = computedApps.${name};
        in
        {
          name = "URL_${lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] name)}";
          value = app.url;
        }
      ) appNames
    )
  );

  # Apps that need vhosts
  appsWithVhosts = lib.filter (name: computedApps.${name}.domain != null) appNames;
in
{
  imports = [
    ./options.nix
  ];

  config = lib.mkIf (rawApps != { }) {
    # Expose ports as environment variables
    stackpanel.devshell.env = appEnvVars // appUrlEnvVars;

    # Register Caddy sites for apps with domains
    stackpanel.devshell.hooks.after = [
      (lib.concatMapStrings (
        name:
        let
          app = computedApps.${name};
        in
        ''
          # Register Caddy site for ${name}
          ${lib.optionalString (app.tls && stepEnabled) ''
            # Generate Step CA certificate for ${app.domain} if needed
            _step_cert="$HOME/.step/certs/${app.domain}.crt"
            _step_key="$HOME/.step/certs/${app.domain}.key"
            if [ ! -f "$_step_cert" ] || [ ! -f "$_step_key" ]; then
              step ca certificate "${app.domain}" "$_step_cert" "$_step_key" \
                --ca-url "${stepCaUrl}" \
                --provisioner "${stepCaCfg.provisioner or "default"}" \
                --not-after 720h \
                --force 2>/dev/null || true
            fi
          ''}
          ${caddyScripts.caddyAddSite}/bin/caddy-add-site "${app.domain}" "localhost:${toString app.port}" --project "${portsCfg.project-name}" ${
            if app.tls && stepEnabled then
              ''--tls-cert "$HOME/.step/certs/${app.domain}.crt" --tls-key "$HOME/.step/certs/${app.domain}.key"''
            else
              lib.optionalString app.tls "--tls-internal"
          } 2>/dev/null || true
        ''
      ) appsWithVhosts)
    ];

    # Add to MOTD
    stackpanel.motd.commands = lib.mkIf (appsWithVhosts != [ ]) [
      {
        name = "Apps:";
        description = lib.concatMapStringsSep ", " (
          name: "${name}=${computedApps.${name}.domain}"
        ) appsWithVhosts;
      }
    ];
  };
}
