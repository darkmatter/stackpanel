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

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/go";
  };

  messages = {
    # Root Step CA configuration
    StepCa = proto.mkMessage {
      name = "StepCa";
      description = "Step CA certificate management configuration for local HTTPS";
      fields = {
        config = proto.message "StepCaConfig" 1 "Step CA configuration";
      };
    };

    # Step CA configuration details
    StepCaConfig = proto.mkMessage {
      name = "StepCaConfig";
      description = "Step CA certificate management configuration";
      fields = {
        enable = proto.bool 1 "Enable Step CA certificate management";
        ca_url = proto.string 2 "Step CA server URL (e.g., https://ca.internal:443)";
        ca_fingerprint = proto.string 3 "Step CA root certificate fingerprint for verification";
        provisioner = proto.string 4 "Step CA provisioner name";
        cert_name = proto.string 5 "Common name for the device certificate";
        prompt_on_shell = proto.bool 6 "Prompt for certificate setup on shell entry if not configured";
      };
    };
  };
}
