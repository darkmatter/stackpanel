# ==============================================================================
# network.nix
#
# Step CA certificate management module for devenv.
#
# This module integrates with a Step CA server to provide automatic device
# certificate provisioning and renewal. Certificates enable:
#   - Secure TLS connections to internal services
#   - AWS Roles Anywhere authentication (passwordless AWS access)
#   - Database authentication without passwords
#
# Features:
#   - Interactive setup prompts on shell entry
#   - Automatic certificate renewal
#   - Skip option for developers who don't need cert auth
#
# Usage:
#   stackpanel.network.step = {
#     enable = true;
#     ca-url = "https://ca.internal:443";
#     ca-fingerprint = "...";
#   };
# ==============================================================================
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.step-ca;
  util = config.stackpanel.util;
  # Use fallback for standalone evaluation (docs generation, nix eval, etc.)
  dirs = config.stackpanel.dirs or { state = ".stack/profile"; profile = ".stack/profile"; };
  stateDir = "${dirs.state}/step";
  skipFile = "${stateDir}/.skip-setup-prompt";

  # Import shared Step CA library
  stepLib = import ../lib/services/step.nix { inherit pkgs lib; };
in
{
  config = lib.mkIf cfg.enable (
    let
      # Create scripts using shared library - only evaluated when enabled
      stepScripts = stepLib.mkStepScripts {
        inherit stateDir;
        caUrl = cfg.ca-url;
        caFingerprint = cfg.ca-fingerprint;
        provisioner = cfg.provisioner;
        certName = cfg.cert-name;
      };

      info = lib.concatStringsSep "\n" [
        "Step CA provides secure TLS certificates for internal services."
        "With a device certificate, you can:"
        ""
        "  • Access internal APIs and services securely"
        "  • Authenticate to AWS using Roles Anywhere"
        "  • Connect to databases without passwords"
        ""
        "Your certificate will be stored locally and renewed automatically."
      ];

      # Non-blocking cert-status notice. Never prompts: silent when the cert is
      # valid, in non-interactive shells, or when opted out; otherwise prints a
      # single hint line in an interactive terminal. Run 'ensure-device-cert' to
      # provision. (The device cert is gitignored runtime state, so it is absent
      # after every fresh clone; a blocking prompt here would re-fire endlessly.)
      interactiveSetup = pkgs.writeShellScriptBin "step-cert-setup-prompt" ''
        set -uo pipefail

        # Cert already present/valid -> nothing to do.
        if ${stepScripts.checkCert}/bin/check-device-cert >/dev/null 2>&1; then
          ${util.log.debug "device cert valid; no notice"}
          exit 0
        fi

        # Stay completely silent in non-interactive shells (CI, editor remote
        # shells, agents) and when the user has opted out. Never block on input.
        if [[ ! -t 0 || ! -t 1 ]]; then exit 0; fi
        if [[ -f "${skipFile}" ]]; then exit 0; fi

        # Interactive terminal, cert missing: one-line non-blocking hint.
        ${pkgs.gum}/bin/gum style --foreground 245 \
          "ℹ  No device cert. Run 'ensure-device-cert' to enable Step CA + AWS auth."
      '';
    in
    {
      stackpanel.devshell.packages = stepScripts.allPackages ++ [
        pkgs.gum
        interactiveSetup
      ];

      stackpanel.motd.commands = [
        {
          name = "ensure-device-cert";
          description = "Request/renew device certificate";
        }
        {
          name = "check-device-cert";
          description = "Verify certificate status";
        }
      ];
      stackpanel.motd.features = [ "Step CA certificates (${cfg.ca-url})" ];

      stackpanel.devshell.hooks.main = lib.mkIf cfg.prompt-on-shell [
        ''
          ${util.log.debug "step-ca: running interactive setup prompt"}
          # Interactive Step CA cert setup
          ${interactiveSetup}/bin/step-cert-setup-prompt
          ${util.log.debug "step-ca: setup prompt complete"}
        ''
      ];
    }
  );
}
