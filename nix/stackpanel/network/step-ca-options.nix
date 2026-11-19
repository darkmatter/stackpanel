# ==============================================================================
# step-ca.nix
#
# Step CA certificate management options.
#
# This module imports options from the proto schema (db/schemas/step-ca.proto.nix)
# and extends them with any Nix-specific runtime options.
#
# The proto schema is the SINGLE SOURCE OF TRUTH for the data structure.
# ==============================================================================
{ config, lib, ... }:
let
  # Import the db module to get proto-derived options
  db = import ../db { inherit lib; };
in
{
  # Step CA options derived from proto schema
  # The proto defines: enable, ca_url, ca_fingerprint, provisioner, cert_name, prompt_on_shell
  # These are converted to kebab-case: ca-url, ca-fingerprint, cert-name, prompt-on-shell
  options.stackpanel.step-ca = db.asOptions db.extend.stepCa;

  config.stackpanel.modules.step-ca = {
    inherit (config.stackpanel.step-ca) enable;
    enablePath = "step-ca.enable";
    meta = {
      name = "Step CA";
      description = "Provision and renew local device certificates.";
      category = "security";
      icon = "shield-check";
    };
    features = {
      packages = true;
      healthchecks = true;
    };
    healthcheckModule = "step-ca";
  };
}
