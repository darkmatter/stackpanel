# ==============================================================================
# step-ca.proto.nix
#
# Protobuf schema for Step CA configuration.
# Defines Step CA certificate management configuration for local HTTPS.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "step_ca.proto";
  package = "stackpanel.db";

  boilerplate = ''
    # step-ca.nix - Step CA certificate configuration
    # type: stackpanel.step-ca
    # See: https://stackpanel.dev/docs/step-ca
    {
      # config = {
      #   enable = true;
      #   ca-url = "https://ca.internal:443";
      #   ca-fingerprint = "abc123...";  # Root CA fingerprint for verification
      #   provisioner = "admin";
      #   cert-name = "dev-workstation";
      #   prompt-on-shell = true;
      # };
    }
  '';

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  messages = {
    # Root Step CA configuration
    StepCa = proto.mkMessage {
      name = "StepCa";
      description = "Step CA certificate management configuration for local HTTPS";
      fields = {
        config = proto.withExample {
          enable = true;
          "ca-url" = "https://ca.internal:443";
          provisioner = "admin";
          "cert-name" = "dev-workstation";
        } (proto.message "StepCaConfig" 1 ''
          Step CA client configuration used to bootstrap and renew local TLS
          certificates for Stackpanel-managed services.
        '');
      };
    };

    # Step CA configuration details
    StepCaConfig = proto.mkMessage {
      name = "StepCaConfig";
      description = "Step CA certificate management configuration";
      fields = {
        enable = proto.withExample true (
          proto.bool 1 ''
            Enable Stackpanel Step CA integration for local TLS certificate management.

            When enabled, Stackpanel adds certificate helper commands and can prompt on shell
            entry to provision or renew the device certificate used by local HTTPS services.
          ''
        );
        ca_url = proto.withExample "https://ca.internal:443" (
          proto.string 2 ''
            Step CA server base URL used by `step` CLI commands.

            Include scheme and port when needed, for example `https://ca.internal:443`. This is
            the CA endpoint used to fetch roots, verify fingerprints, and request certificates.
          ''
        );
        ca_fingerprint = proto.withExample "abc123def456abc123def456abc123def456abc123def456abc123def456" (
          proto.string 3 ''
            Expected root CA fingerprint used to verify the Step CA server before trusting it.

            Get this from your CA bootstrap output or `step certificate fingerprint root_ca.crt`.
            Keep it stable in shared config so every developer verifies the same CA root.
          ''
        );
        provisioner = proto.withExample "admin" (
          proto.string 4 ''
            Step CA provisioner name used when requesting local certificates.

            This must match a provisioner configured on the CA, such as `admin`, `developer`, or
            an OIDC provisioner name. The selected provisioner controls auth flow and cert policy.
          ''
        );
        cert_name = proto.withExample "dev-workstation" (
          proto.string 5 ''
            Common name for the local device certificate.

            Use a stable workstation or developer identity, for example `alice-mbp` or
            `dev-workstation`. Service modules may use this name when locating or displaying the
            generated certificate.
          ''
        );
        prompt_on_shell = proto.withExample true (
          proto.bool 6 ''
            Prompt during devshell entry when Step CA is enabled but the local certificate is
            missing, expired, or not yet trusted.

            Set false for CI or non-interactive shells; developers can still run the certificate
            helper commands manually.
          ''
        );
      };
    };
  };
}
