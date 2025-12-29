# ==============================================================================
# network.nix
#
# Network options - Step CA certificate management for local HTTPS.
#
# Configures Step CA integration for automatic TLS certificate management.
# This enables HTTPS for local development with trusted certificates.
#
# Options:
#   - enable: Enable Step CA certificate management
#   - ca-url: Step CA server URL (e.g., https://ca.internal:443)
#   - ca-fingerprint: Root certificate fingerprint for verification
#   - provisioner: Step CA provisioner name (e.g., "Authentik")
#   - cert-name: Common name for the device certificate
#   - prompt-on-shell: Prompt for setup if not configured
#
# Certificates are used by:
#   - Caddy for HTTPS reverse proxy
#   - AWS Roles Anywhere for IAM role assumption
#   - Other services requiring mutual TLS
# ==============================================================================
{ lib, ... }: {
  options.stackpanel.network.step = {
    enable = lib.mkEnableOption "Step CA certificate management";

    ca-url = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Step CA URL (e.g., https://ca.internal:443)";
    };

    ca-fingerprint = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Step CA root certificate fingerprint";
    };

    provisioner = lib.mkOption {
      type = lib.types.str;
      default = "Authentik";
      description = "Step CA provisioner name";
    };

    cert-name = lib.mkOption {
      type = lib.types.str;
      default = "device";
      description = "Common name for the device certificate";
    };

    prompt-on-shell = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Prompt for certificate setup on shell entry if not configured";
    };
  };
}
