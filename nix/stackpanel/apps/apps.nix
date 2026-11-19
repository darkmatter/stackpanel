# ==============================================================================
# apps.nix
#
# Application port management and Caddy virtual host configuration for devenv.
#
# Export the same port and domain that the rest of Stackpanel reads from
# appsComputed. Caddy and PORT_<APP> must agree about the upstream port.
#
# Domain Format:
#   Virtual hosts use the format: <app>.<project>.<tld>
#   Example: web.myproject.localhost, api.myproject.lan
#   The TLD is configured via stackpanel.caddy.tld (default: "localhost")
#
# Usage:
#   stackpanel.apps = {
#     web = {};                          # Deterministic port; no vhost
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
  caddyCfg = config.stackpanel.caddy;
  dirs = config.stackpanel.dirs or { gen = ".stack/gen"; };

  # Import caddy library for the pure site-rendering helpers. Per-site files are
  # generated declaratively via stackpanel.files.entries (see config below) —
  # `stack caddy add` only links them into the global proxy.
  caddyLib = import ../integrations/services/caddy { inherit pkgs lib; };
  stepCaCfg = config.stackpanel.step-ca or { enable = false; };
  stepCaUrl = stepCaCfg.ca-url or "";
  useStepTls = caddyCfg.use-step-tls or false;
  stepEnabled = useStepTls && (stepCaCfg.enable or false);

  computedApps = config.stackpanel.appsComputed;
  appNames = lib.attrNames computedApps;

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
  ];

  config = lib.mkIf (rawApps != { }) {
    # Expose ports as environment variables
    stackpanel.devshell.env = appEnvVars // appUrlEnvVars;

    # Generate per-site Caddyfile snippets functionally into .stack/gen/caddy/.
    #
    # This is the deterministic source of truth for each site. `write-files`
    # materializes these on devshell entry; the Go CLI (`stack caddy add`)
    # only links them into the shared proxy and never writes them. TLS cert
    # paths use Caddy's {$HOME} placeholder so the snippet stays pure (no
    # eval-time $HOME).
    stackpanel.files.entries = lib.listToAttrs (
      map (
        name:
        let
          app = computedApps.${name};
          tls =
            if app.tls && stepEnabled then
              "tls {$HOME}/.step/certs/${app.domain}.crt {$HOME}/.step/certs/${app.domain}.key"
            else if app.tls then
              "tls internal"
            else
              "";
        in
        lib.nameValuePair "${dirs.gen}/caddy/${caddyLib.sanitizeDomain app.domain}.caddy" {
          format = "text";
          text = caddyLib.renderSite {
            inherit (app) domain;
            upstream = "localhost:${toString app.port}";
            inherit tls;
          };
          source = "caddy";
          description = "Caddy reverse-proxy site for ${name} (${app.domain})";
        }
      ) appsWithVhosts
    );

    # On devshell entry: provision Step CA certs (imperative — needs the CA),
    # then link this project's generated snippets into the global proxy. Runs in
    # the `after` phase so the .stack/gen/caddy/ files (written by `write-files`
    # in the `main` phase) already exist.
    stackpanel.devshell.hooks.after = lib.optional (appsWithVhosts != [ ]) (
      (lib.concatMapStrings (
        name:
        let
          app = computedApps.${name};
        in
        lib.optionalString (app.tls && stepEnabled) ''
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
        ''
      ) appsWithVhosts)
      + ''
        # Link this project's generated Caddy sites (.stack/gen/caddy/*.caddy)
        # into the shared ~/.config/caddy/sites.d/. Generation happened above
        # via stackpanel.files.entries; this only creates/refreshes symlinks.
        # Kept quiet on entry; run `stack caddy add` manually for output.
        if command -v stack >/dev/null 2>&1; then
          stack caddy add >/dev/null 2>&1 || true
        fi
      ''
    );

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
