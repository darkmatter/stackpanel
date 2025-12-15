# Network module - Step CA certificate management
# Standalone module - no flake-parts dependency
#
# Usage:
#   stackpanel.network.step = {
#     enable = true;
#     caUrl = "https://ca.internal:443";
#     caFingerprint = "...";
#   };
#
{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.stackpanel.network.step;
  stackpanelCfg = config.stackpanel;

  # Import shared network library
  networkLib = import ../../lib/network.nix {inherit pkgs lib;};

  # Create scripts using shared library
  stepScripts = networkLib.mkStepScripts {
    inherit (cfg) stateDir caUrl caFingerprint provisioner certName;
  };
in {
  # Note: tailscale.nix is empty, step.nix is now superseded by lib/network.nix

  options.stackpanel.network.step = {
    enable = lib.mkEnableOption "Step CA certificate management";

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "${stackpanelCfg.stateDir}/step";
      description = "Directory for Step CA state (certs, keys)";
    };

    caUrl = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Step CA URL (e.g., https://ca.internal:443)";
    };

    caFingerprint = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Step CA root certificate fingerprint";
    };

    provisioner = lib.mkOption {
      type = lib.types.str;
      default = "Authentik";
      description = "Step CA provisioner name";
    };

    certName = lib.mkOption {
      type = lib.types.str;
      default = "device";
      description = "Common name for the device certificate";
    };
  };

  config = lib.mkIf cfg.enable {
    # Export packages for use in devShells or other modules
    stackpanel.packages = {
      check-device-cert = stepScripts.checkCert;
      ensure-device-cert = stepScripts.ensureCert;
      renew-device-cert = stepScripts.renewCert;
    };
  };
}
